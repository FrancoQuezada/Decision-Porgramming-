"""Prepare/run a 4-variant x 2-bound Sequential IR-B&B ablation campaign."""
import argparse
from collections import Counter
import importlib.util
import json
import os
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
BASE_DIR=ROOT/'scripts/sequential_informative_cplex'
spec=importlib.util.spec_from_file_location('sequential_informative_base',BASE_DIR/'benchmark.py')
B=importlib.util.module_from_spec(spec); spec.loader.exec_module(B)
scheduler=B.scheduler; phase4_protocol=B.phase4_protocol
VARIANTS=('baseline','reachability','cost_aware','combined')
BOUNDS=('full_information','legacy_nonsequential')
DEFAULT_SOURCE=ROOT/'experiments/results/sequential_informative_2026_11'
GIB=1024**3


def digest(path): return B.digest(path)


def configuration(source,output):
    c=B.configuration(source,output)
    c['hardware']['max_concurrent_jobs']=8
    c['parallelism'].update(small_max_jobs=8,medium_max_jobs=8,large_max_jobs=8)
    c['execution']['target_concurrent_jobs']=8
    c['execution']['output_directory']=str(output.relative_to(ROOT))
    c['execution']['manifest']=str((source/'manifest.toml').relative_to(ROOT))
    return c


def jobs_for(chosen,c):
    jobs=[]
    for instance in chosen:
        for variant in VARIANTS:
            for bound in BOUNDS:
                method=f'irbb_{variant}_{bound}'
                job=dict(instance,algorithm='irbb',method=method,variant=variant,bound=bound,
                    solver_configuration='none',job_id=f"{instance['instance_id']}__{variant}__{bound}",
                    tier=scheduler.tier_of(instance['tests']),estimated_memory_bytes=GIB,
                    time_seconds=c['limits']['time_seconds'],progress_every=10000,
                    solver_config=str(ROOT/c['execution']['solver_config']))
                job.update(scheduler.reservation_details(job,c)); jobs.append(job)
    if len(jobs)!=200 or len({job['job_id'] for job in jobs})!=200:
        raise ValueError('ablation requires 25 instances x 4 variants x 2 bounds = 200 jobs')
    return sorted(jobs,key=lambda j:(j['tests'],j['instance_id'],VARIANTS.index(j['variant']),BOUNDS.index(j['bound'])))


def current_protocol(c,chosen):
    protocol=scheduler.fingerprint(c,{'instances':chosen})
    files=sorted(p for p in HERE.iterdir() if p.suffix in ('.jl','.py'))
    protocol['scientific']['source_hashes'].update(
        {str(path.relative_to(ROOT)):digest(path) for path in files})
    protocol['scientific']['sequential_irbb_ablation']=dict(
        variants=list(VARIANTS),bounds=list(BOUNDS),instances=25,jobs=200,
        branching='first unfixed row; skip-first DFS for every variant',
        arithmetic='exact Rational{BigInt}',reference='independent exact sequential DP')
    protocol['scientific_sha256']=phase4_protocol.object_hash(protocol['scientific'])
    return protocol


def command_for_job(job,c,folder,root):
    scheduler.atomic_json(folder/'job.json',job)
    (folder/'job.toml').write_text(scheduler.toml.dumps(job))
    return [os.environ.get('DP_BENCHMARK_JULIA','julia'),
        '--project='+str(ROOT/'environments/cplex'),'--startup-file=no','--history-file=no',
        '--threads=1','--gcthreads=1,0',str(HERE/'worker.jl'),str(folder)]


def prepare(output,source):
    output=output.resolve(); source=source.resolve()
    if output.exists(): raise ValueError('output exists; resume instead of overwriting')
    chosen=B.selection(source); c=configuration(source,output); jobs=jobs_for(chosen,c)
    output.mkdir(parents=True)
    scheduler.atomic_json(output/'configuration.json',c)
    scheduler.atomic_json(output/'selection.json',chosen)
    scheduler.atomic_json(output/'plan.json',jobs)
    phase4_protocol.authorize_execution(output,current_protocol(c,chosen),scheduler.atomic_json)
    print(f'Prepared {len(jobs)} jobs on {len(chosen)} immutable inputs; no workers launched')


def load(output):
    output=output.resolve(); c=json.loads((output/'configuration.json').read_text())
    chosen=json.loads((output/'selection.json').read_text()); jobs=jobs_for(chosen,c)
    if jobs!=json.loads((output/'plan.json').read_text()): raise ValueError('saved plan changed')
    return c,chosen,jobs


def run(output):
    output=output.resolve(); c,chosen,jobs=load(output)
    for job in jobs:
        if digest(ROOT/job['instance'])!=job['file_sha256']:
            raise ValueError('input checksum changed: '+job['instance_id'])
    scheduler.command_for_job=command_for_job
    return scheduler.execute_campaign(jobs,c,output,current_protocol(c,chosen))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command',choices=('prepare','run','resume','status'))
    parser.add_argument('output',type=Path)
    parser.add_argument('--source',type=Path,default=DEFAULT_SOURCE)
    args=parser.parse_args()
    if args.command=='prepare': prepare(args.output,args.source)
    elif args.command in ('run','resume'): raise SystemExit(run(args.output))
    else:
        c,chosen,jobs=load(args.output)
        print(json.dumps(dict(scheduler.job_states(jobs,args.output.resolve()),
            statuses=Counter(r['status'] for r in scheduler.read_results(args.output.resolve()).values())),
            indent=2,default=dict))
