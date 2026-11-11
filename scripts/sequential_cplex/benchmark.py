"""Five-instance sequential adapter to the existing Phase-4 resource scheduler.

No old scheduler/worker/campaign is modified. The production command constructor
is supplied at the module boundary; the scheduler's test-only injection is unused.
All optimization and physical validation run in the existing locked Julia env.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[2]
PHASE4 = ROOT / 'scripts/phase4_extended'
sys.path.insert(0, str(PHASE4))
import benchmark as scheduler
import protocol as phase4_protocol

HERE = Path(__file__).resolve().parent
CATALOG = ROOT / 'experiments/table3_sequential/frozen_julia1103'
METHODS = ('rdp', 'rjt', 'irbb_fi', 'irbb_legacy')
GIB = 1024 ** 3


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def size_guard(method, m):
    if method == 'rdp' and 2 * 8 ** m > 200000:
        return f'RDP_SEGMENT_GUARD: {2*8**m} > 200000'
    if method == 'rjt' and m > 5:
        return f'RJT_TEST_GUARD: {m} > 5'
    if method.startswith('irbb') and sum(4**i for i in range(m)) > 24:
        return f'IRBB_POLICY_ROW_GUARD: {sum(4**i for i in range(m))} > 24'
    return None


def configuration(output):
    return dict(
        hardware=dict(logical_processors=os.cpu_count(), total_ram_gib=32,
            reserved_system_ram_gib=3, global_experiment_ram_gib=24,
            max_concurrent_jobs=4, threads_per_job=1),
        parallelism=dict(small_max_jobs=4, medium_max_jobs=2, large_max_jobs=1),
        limits=dict(time_seconds=3600., per_job_memory_gib=16,
            initialization_seconds=300, validation_seconds=300, termination_grace_seconds=2),
        execution=dict(run_on_setup=False, resume_completed=True, poll_seconds=.1,
            queue_notice_seconds=30, warmup=True, output_directory=str(output.relative_to(ROOT)),
            manifest='experiments/table3_sequential/frozen_julia1103/manifest.toml',
            cplex_project='environments/cplex', solver_config='experiments/phase4_extended/cplex.toml',
            memory_calibration='not_applicable_new_sequential_models', idle_timeout_seconds=60,
            tree_scan_seconds=.5, target_concurrent_jobs=4),
        experiments=dict(min_tests=1, max_tests=8, instances_per_size=5,
            original_seed_indices=[1, 2, 3, 4, 5], informative_seeds=[], informative_profile='source-replay'),
        tolerances=dict(absolute=1e-7, relative=1e-9),
        memory_reservations=dict(small_gib=2, medium_gib=5, large_gib=10, calibrated_min_gib=1,
            original_gib_by_tests=[2,2,3,5,10,16,16,16],
            corrected_gib_by_tests=[2,2,3,5,10,16,16,16], irbb_gib_by_tests=[2,2,3,5,10,16,16,16]),
        memory_estimates=dict(base_gib=1, bytes_per_variable=200, bytes_per_matrix_term=80,
            bytes_per_coefficient=16, safety_factor=1.5, observed_safety_factor=1.25,
            observed_margin_gib=.25, censored_safety_factor=1.5, minimum_samples=3,
            reservation_quantum_gib=.25, rss_growth_margin_gib=.125))


def selection():
    manifest = scheduler.read_toml(CATALOG / 'manifest.toml')
    chosen = [r for r in manifest['records'] if r['seed_id'] in range(1, 6)]
    if len(chosen) != 40 or any(sum(r['M'] == m for r in chosen) != 5 for m in range(1, 9)):
        raise ValueError('Require exactly the first five archived indices at every M')
    for r in chosen:
        if digest(CATALOG / r['instance_file']) != r['file_sha256']:
            raise ValueError('Frozen input changed: ' + r['id'])
    return sorted(chosen, key=lambda r: (r['M'], r['seed_id']))


def jobs_for(chosen, c):
    jobs = []
    for r in chosen:
        m = r['M']
        for method in METHODS:
            # Phase-4 resource classes only; method is the scientific algorithm.
            resource_class = 'irbb' if method.startswith('irbb') else 'corrected'
            nv = 2 * 8**m + 2 * 4**m + 2 * sum(4**i for i in range(m))
            terms = (m + 2) * 2 * 8**m
            estimate = int(1.5 * (GIB + 200*nv + 80*terms)) if resource_class != 'irbb' else GIB
            job = dict(instance_id=r['id'], dataset='archived_sequential', profile='source-replay-julia1103',
                seed=r['archived_seed'], seed_index=r['seed_id'], tests=m, states=3, reports=3,
                instance=str((CATALOG/r['instance_file']).relative_to(ROOT)), instance_hash=r['instance_sha256'],
                file_sha256=r['file_sha256'], raw_snapshot=str((CATALOG/r['raw_file']).relative_to(ROOT)),
                raw_hash=r['raw_file_sha256'], algorithm=resource_class, method=method,
                solver_configuration='none' if resource_class == 'irbb' else 'CPLEX-Default',
                job_id=f"{r['id']}__{method}", tier=scheduler.tier_of(m),
                estimated_memory_bytes=estimate, time_seconds=c['limits']['time_seconds'],
                solver_config=str(ROOT / c['execution']['solver_config']))
            job.update(scheduler.reservation_details(job, c))
            reason = size_guard(method, m)
            if reason:
                job['size_guard_reason'] = reason
            jobs.append(job)
    return jobs


def current_protocol(c, chosen):
    p = scheduler.fingerprint(c, chosen)
    files = [p for p in HERE.iterdir() if p.suffix in ('.jl', '.py')]
    files += [ROOT/'scripts/benchmark_sequential_oil.jl', CATALOG/'manifest.toml']
    p['scientific']['source_hashes'].update({str(f.relative_to(ROOT)): digest(f) for f in files})
    p['scientific']['sequential_contract'] = dict(methods=list(METHODS), indices=[1,2,3,4,5],
        dense_rdp=True, rjt='existing corrected package formulation',
        guards=dict(rdp_segments=200000, rjt_tests=5, irbb_rows=24),
        exact_policy_reference='independent sequential belief-state DP',
        timing='Phase-4 measured solve including preparation/recovery; independent validation excluded')
    p['scientific_sha256'] = phase4_protocol.object_hash(p['scientific'])
    return p


def command_for_job(job, c, folder, root):
    scheduler.atomic_json(folder/'job.json', job)
    (folder/'job.toml').write_text(scheduler.toml.dumps(job))
    return [os.environ.get('DP_BENCHMARK_JULIA', 'julia'), '--project='+str(ROOT/'environments/cplex'),
        '--startup-file=no', '--history-file=no', '--threads=1', '--gcthreads=1,0',
        str(HERE/'worker.jl'), str(folder)]


def prepare(output):
    if output.exists():
        raise ValueError('Output exists; resume it instead of overwriting')
    c = configuration(output)
    chosen = selection()
    jobs = jobs_for(chosen, c)
    output.mkdir(parents=True)
    scheduler.atomic_json(output/'configuration.json', c)
    scheduler.atomic_json(output/'selection.json', chosen)
    scheduler.atomic_json(output/'plan.json', jobs)
    p = current_protocol(c, chosen)
    provenance = phase4_protocol.authorize_execution(output, p, scheduler.atomic_json)
    for job in jobs:
        if job.get('size_guard_reason'):
            scheduler.atomic_json(scheduler.terminal_path(output, job), dict(job, **provenance,
                status='SKIPPED_SIZE_GUARD', attempted=False, certified_optimal=False,
                feasibility_status='UNAVAILABLE', termination_reason=job['size_guard_reason']))
    shutil.copyfile(ROOT/'scripts/table3_sequential/PublishedTable3.csv', output/'published_gurobi_reference.csv')
    print(f'Prepared 40 frozen physical inputs and 160 jobs (including explicit guard exclusions): {output}')


def run(output, methods, sizes):
    c = json.loads((output/'configuration.json').read_text())
    chosen = json.loads((output/'selection.json').read_text())
    if chosen != selection():
        raise ValueError('Frozen selection changed')
    jobs = jobs_for(chosen, c)
    selected = [j for j in jobs if j['method'] in methods and j['tests'] in sizes]
    if not selected:
        raise ValueError('No selected jobs')
    if any(m.startswith('irbb') for m in methods):
        rows = scheduler.read_results(output)
        for j in selected:
            if j.get('size_guard_reason'):
                continue
            for baseline in ('rdp','rjt'):
                if not rows.get(j['instance_id']+'__'+baseline,{}).get('certified_optimal'):
                    raise ValueError('Certified paired RDP/RJT prerequisite missing: '+j['instance_id'])
    # Reuse the complete Phase-4 process scheduler, admission rules, monitoring,
    # watchdogs, locking and resume. The older command/test injection is unused.
    scheduler.command_for_job = command_for_job
    return scheduler.execute_campaign(selected, c, output, current_protocol(c, chosen))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=('prepare','run','status'))
    parser.add_argument('output', type=Path)
    parser.add_argument('--methods', default='rdp,rjt')
    parser.add_argument('--sizes', default='1,2,3')
    args = parser.parse_args()
    dest = args.output.resolve()
    if args.command == 'prepare':
        prepare(dest)
    elif args.command == 'run':
        methods = args.methods.split(','); sizes = [int(x) for x in args.sizes.split(',')]
        if any(m not in METHODS for m in methods) or any(m not in range(1,9) for m in sizes):
            parser.error('Unknown method or size')
        raise SystemExit(run(dest,methods,sizes))
    else:
        rows = scheduler.read_results(dest)
        from collections import Counter
        print(Counter(r['status'] for r in rows.values()))
