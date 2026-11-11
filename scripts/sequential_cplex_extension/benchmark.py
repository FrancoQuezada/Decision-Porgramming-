"""Run only the 80 sequential jobs excluded by the baseline size guards."""
import argparse
from collections import Counter
import importlib.util
import json
import os
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
BASE_DIR = ROOT / 'scripts/sequential_cplex'
spec = importlib.util.spec_from_file_location('sequential_cplex_base', BASE_DIR/'benchmark.py')
B = importlib.util.module_from_spec(spec)
spec.loader.exec_module(B)
scheduler = B.scheduler
phase4_protocol = B.phase4_protocol
METHODS = B.METHODS


def digest(path):
    return B.digest(path)


def selection():
    return B.selection()


def configuration(output):
    c = B.configuration(output)
    c['execution']['output_directory'] = str(output.relative_to(ROOT))
    return c


def is_extension_job(job):
    m, method = job['tests'], job['method']
    return (method in ('rdp','rjt') and m >= 6) or (method.startswith('irbb') and m >= 4)


def jobs_for(chosen, c):
    jobs = []
    for job in B.jobs_for(chosen, c):
        if not is_extension_job(job):
            continue
        job.pop('size_guard_reason', None)
        m = job['tests']
        job.update(size_guard_override=True,
            former_guard='rdp_segments' if job['method']=='rdp' else
                'rjt_tests' if job['method']=='rjt' else 'irbb_policy_rows',
            rdp_max_segments=2*8**m, rjt_max_tests=m,
            irbb_max_rows=sum(4**i for i in range(m)))
        jobs.append(job)
    if len(jobs) != 80:
        raise ValueError(f'Require exactly 80 former-guard jobs, got {len(jobs)}')
    return jobs


def current_protocol(c, chosen):
    p = B.current_protocol(c, chosen)
    files = list(HERE.glob('*.jl')) + list(HERE.glob('*.py'))
    p['scientific']['source_hashes'].update(
        {str(f.relative_to(ROOT)): digest(f) for f in files})
    p['scientific']['sequential_contract'] = dict(
        methods=list(METHODS), indices=[1,2,3,4,5],
        selected_jobs='only the 80 jobs excluded by the baseline logical size guards',
        logical_size_guards='removed by explicit user request',
        retained_limits=dict(total_wall_seconds=3600, process_memory_gib=16,
            initialization_seconds=300, validation_seconds=300),
        dense_rdp=True, rjt='existing corrected package formulation',
        exact_policy_reference='independent sequential belief-state DP',
        warmup='M=1 compilation path; complete actual construction is measured')
    p['scientific_sha256'] = phase4_protocol.object_hash(p['scientific'])
    return p


def command_for_job(job, c, folder, root):
    scheduler.atomic_json(folder/'job.json', job)
    (folder/'job.toml').write_text(scheduler.toml.dumps(job))
    return [os.environ.get('DP_BENCHMARK_JULIA', 'julia'),
        '--project='+str(ROOT/'environments/cplex'), '--startup-file=no',
        '--history-file=no', '--threads=1', '--gcthreads=1,0',
        str(HERE/'worker.jl'), str(folder)]


def prepare(output):
    if output.exists():
        raise ValueError('Output exists; resume it instead of overwriting')
    c=configuration(output); chosen=selection(); jobs=jobs_for(chosen,c)
    output.mkdir(parents=True)
    scheduler.atomic_json(output/'configuration.json',c)
    scheduler.atomic_json(output/'selection.json',chosen)
    scheduler.atomic_json(output/'plan.json',jobs)
    phase4_protocol.authorize_execution(output,current_protocol(c,chosen),scheduler.atomic_json)
    shutil.copyfile(ROOT/'scripts/table3_sequential/PublishedTable3.csv',
        output/'published_gurobi_reference.csv')
    print(f'Prepared 80 former-guard jobs on 40 frozen inputs: {output}')


def run(output, methods, sizes):
    c=json.loads((output/'configuration.json').read_text())
    chosen=json.loads((output/'selection.json').read_text())
    if chosen != selection():
        raise ValueError('Frozen selection changed')
    selected=[j for j in jobs_for(chosen,c)
        if j['method'] in methods and j['tests'] in sizes]
    if not selected:
        raise ValueError('No selected extension jobs')
    scheduler.command_for_job=command_for_job
    return scheduler.execute_campaign(selected,c,output,current_protocol(c,chosen))


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('command',choices=('prepare','run','status'))
    parser.add_argument('output',type=Path)
    parser.add_argument('--methods',default=','.join(METHODS))
    parser.add_argument('--sizes',default='4,5,6,7,8')
    args=parser.parse_args(); output=args.output.resolve()
    if args.command=='prepare':
        prepare(output)
    elif args.command=='run':
        methods=args.methods.split(','); sizes=[int(x) for x in args.sizes.split(',')]
        if any(x not in METHODS for x in methods) or any(x not in range(1,9) for x in sizes):
            parser.error('Unknown method or size')
        raise SystemExit(run(output,methods,sizes))
    else:
        print(Counter(r['status'] for r in scheduler.read_results(output).values()))
