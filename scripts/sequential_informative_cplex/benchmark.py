"""Prepare and run a 25-instance/100-run sequential Oil campaign.

Importing this module and the ``prepare`` command never launch a worker.
``run`` and ``resume`` delegate process management to the Phase-4 scheduler.
"""
import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import sys

try:
    import tomllib as toml
except ImportError:
    import toml

ROOT = Path(__file__).resolve().parents[2]
PHASE4 = ROOT / 'scripts/phase4_extended'
sys.path.insert(0, str(PHASE4))
import benchmark as scheduler
import protocol as phase4_protocol

HERE = Path(__file__).resolve().parent
METHODS = ('rdp', 'rjt', 'irbb_fi', 'irbb_legacy')
GIB = 1024 ** 3


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def paths(campaign):
    campaign = Path(campaign).resolve()
    try:
        campaign.relative_to(ROOT / 'experiments/results')
    except ValueError as exc:
        raise ValueError('campaign must be below experiments/results') from exc
    return campaign, campaign / 'execution'


def configuration(campaign, output):
    return dict(
        hardware=dict(logical_processors=os.cpu_count() or 1, total_ram_gib=32,
            reserved_system_ram_gib=3, global_experiment_ram_gib=24,
            max_concurrent_jobs=4, threads_per_job=1),
        parallelism=dict(small_max_jobs=4, medium_max_jobs=2, large_max_jobs=1),
        limits=dict(time_seconds=3600., per_job_memory_gib=16,
            initialization_seconds=600, validation_seconds=300, termination_grace_seconds=3),
        execution=dict(run_on_setup=False, resume_completed=True, poll_seconds=.25,
            queue_notice_seconds=30, warmup=True, output_directory=str(output.relative_to(ROOT)),
            manifest=str((campaign/'manifest.toml').relative_to(ROOT)),
            cplex_project='environments/cplex', solver_config='experiments/phase4_extended/cplex.toml',
            memory_calibration='not_applicable_new_sequential_models', idle_timeout_seconds=60,
            tree_scan_seconds=.5, target_concurrent_jobs=4),
        experiments=dict(min_tests=1, max_tests=5, instances_per_size=5,
            original_seed_indices=[], informative_seeds=[], informative_profile='generate_oil-informative-v1'),
        tolerances=dict(absolute=1e-7, relative=1e-9),
        memory_reservations=dict(small_gib=2, medium_gib=5, large_gib=10, calibrated_min_gib=1,
            original_gib_by_tests=[2,2,3,5,10,16,16,16],
            corrected_gib_by_tests=[2,2,3,5,10,16,16,16],
            irbb_gib_by_tests=[2,2,3,5,10,16,16,16]),
        memory_estimates=dict(base_gib=1, bytes_per_variable=200, bytes_per_matrix_term=80,
            bytes_per_coefficient=16, safety_factor=1.5, observed_safety_factor=1.25,
            observed_margin_gib=.25, censored_safety_factor=1.5, minimum_samples=3,
            reservation_quantum_gib=.25, rss_growth_margin_gib=.125))


def selection(campaign):
    manifest_path = campaign / 'manifest.toml'
    manifest = toml.loads(manifest_path.read_text())
    if manifest.get('schema') != 'sequential-informative-oil-v1':
        raise ValueError('run generate.jl and validate_instances.jl first')
    records = manifest['records']
    if len(records) != 25:
        raise ValueError('manifest must contain exactly 25 instances')
    chosen = []
    for record in records:
        path = campaign / record['instance_file']
        if digest(path) != record['file_sha256']:
            raise ValueError('instance file changed: ' + record['id'])
        if not record.get('strictly_informative'):
            raise ValueError('non-informative record: ' + record['id'])
        chosen.append(dict(
            instance_id=record['id'], id=record['id'], dataset='sequential_informative',
            profile='generate_oil-informative-v1', seed=record['seed'], seed_index=record['seed_id'],
            tests=record['M'], M=record['M'], states=record['states'], reports=record['reports'],
            instance=str(path.relative_to(ROOT)), instance_hash=record['instance_sha256'],
            file_sha256=record['file_sha256'], F_empty_exact=record['F_empty_exact'],
            F_full_exact=record['F_full_exact']))
    for m in range(1, 6):
        group = [r for r in chosen if r['tests'] == m]
        if len(group) != 5 or len({r['seed'] for r in group}) != 5:
            raise ValueError(f'exactly five distinct seeds required at M={m}')
    if len({r['instance_hash'] for r in chosen}) != 25:
        raise ValueError('physical instance hashes must be unique')
    return sorted(chosen, key=lambda r: (r['tests'], r['seed_index']))


def dense_rdp_dimensions(m):
    histories = 4 ** m
    rows = sum(4 ** i for i in range(m))
    segments = histories * 2 ** m
    return dict(estimated_variables=2*segments + 2*rows + 2*histories,
                estimated_constraints=3*rows + 4*histories,
                estimated_matrix_terms=(m+2)*2*segments)


def jobs_for(chosen, c):
    jobs = []
    for record in chosen:
        m = record['tests']
        for method in METHODS:
            resource_class = 'irbb' if method.startswith('irbb') else 'corrected'
            dimensions = dense_rdp_dimensions(m) if method == 'rdp' else {}
            estimate = GIB if resource_class == 'irbb' else int(1.5 * (GIB +
                200*dimensions.get('estimated_variables', 4**m) +
                80*dimensions.get('estimated_matrix_terms', (m+2)*8**m)))
            job = dict(record, algorithm=resource_class, method=method,
                solver_configuration='none' if resource_class == 'irbb' else 'CPLEX-Default',
                job_id=f"{record['instance_id']}__{method}", tier=scheduler.tier_of(m),
                estimated_memory_bytes=estimate, time_seconds=c['limits']['time_seconds'],
                solver_config=str(ROOT / c['execution']['solver_config']), **dimensions)
            job.update(scheduler.reservation_details(job, c))
            jobs.append(job)
    if len(jobs) != 100 or len({j['job_id'] for j in jobs}) != 100:
        raise ValueError('campaign plan must contain 100 unique jobs')
    return sorted(jobs, key=lambda j: (j['tests'], j['instance_id'], METHODS.index(j['method'])))


def current_protocol(c, chosen):
    manifest = {'instances': chosen}
    protocol = scheduler.fingerprint(c, manifest)
    files = sorted(p for p in HERE.iterdir() if p.suffix in ('.jl', '.py'))
    files.append(ROOT / 'scripts/benchmark_sequential_oil.jl')
    protocol['scientific']['source_hashes'].update(
        {str(path.relative_to(ROOT)): digest(path) for path in files})
    protocol['scientific']['sequential_contract'] = dict(
        methods=list(METHODS), sizes=list(range(1, 6)), instances_per_size=5,
        dense_rdp=True, rjt='existing sequential package formulation',
        irbb_bounds=['full_information', 'legacy_nonsequential'],
        dimension_guards='disabled with typemax(Int); Phase-4 resource watchdogs retained',
        exact_policy_reference='independent sequential belief-state DP',
        timing='Phase-4 measured solve including preparation/recovery; independent validation excluded')
    protocol['scientific_sha256'] = phase4_protocol.object_hash(protocol['scientific'])
    return protocol


def command_for_job(job, c, folder, root):
    scheduler.atomic_json(folder / 'job.json', job)
    (folder / 'job.toml').write_text(scheduler.toml.dumps(job))
    return [os.environ.get('DP_BENCHMARK_JULIA', 'julia'),
        '--project=' + str(ROOT/'environments/cplex'), '--startup-file=no', '--history-file=no',
        '--threads=1', '--gcthreads=1,0', str(HERE/'worker.jl'), str(folder)]


def prepare(campaign):
    campaign, output = paths(campaign)
    if output.exists():
        raise ValueError('execution directory exists; use run/resume without preparing again')
    chosen = selection(campaign)
    c = configuration(campaign, output)
    jobs = jobs_for(chosen, c)
    output.mkdir(parents=True)
    scheduler.atomic_json(output/'configuration.json', c)
    scheduler.atomic_json(output/'selection.json', chosen)
    scheduler.atomic_json(output/'plan.json', jobs)
    phase4_protocol.authorize_execution(output, current_protocol(c, chosen), scheduler.atomic_json)
    print(f'Prepared 25 inputs and 100 jobs without launching workers: {output}')


def load_prepared(campaign):
    campaign, output = paths(campaign)
    c = json.loads((output/'configuration.json').read_text())
    chosen = json.loads((output/'selection.json').read_text())
    if chosen != selection(campaign):
        raise ValueError('instance selection or hashes changed after prepare')
    jobs = jobs_for(chosen, c)
    if jobs != json.loads((output/'plan.json').read_text()):
        raise ValueError('saved execution plan changed')
    return output, c, chosen, jobs


def run(campaign, retry_failed=False):
    output, c, chosen, jobs = load_prepared(campaign)
    for job in jobs:
        if digest(ROOT/job['instance']) != job['file_sha256']:
            raise ValueError('instance checksum changed: ' + job['instance_id'])
    scheduler.command_for_job = command_for_job
    return scheduler.execute_campaign(jobs, c, output, current_protocol(c, chosen),
                                      retry_failed=retry_failed)


def status(campaign):
    output, _, _, jobs = load_prepared(campaign)
    print(json.dumps(dict(scheduler.job_states(jobs, output),
        statuses=Counter(r['status'] for r in scheduler.read_results(output).values())),
        indent=2, default=dict))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('prepare', 'run', 'resume', 'status'))
    parser.add_argument('campaign', type=Path)
    parser.add_argument('--retry-failed', action='store_true',
        help='rerun terminal failures; interrupted executions are always resumable')
    args = parser.parse_args()
    if args.command == 'prepare':
        prepare(args.campaign)
    elif args.command in ('run', 'resume'):
        raise SystemExit(run(args.campaign, retry_failed=args.retry_failed))
    else:
        status(args.campaign)
