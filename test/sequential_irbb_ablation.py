"""Static ablation-plan checks; never launch Julia or the scheduler."""
import importlib.util
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
HERE=ROOT/'scripts/sequential_irbb_ablation'
spec=importlib.util.spec_from_file_location('irbb_ablation_static',HERE/'benchmark.py')
B=importlib.util.module_from_spec(spec); spec.loader.exec_module(B)


def instances():
    return [dict(instance_id=f'm{m}_i{i}',id=f'm{m}_i{i}',dataset='informative',
        profile='test',seed=100*m+i,seed_index=i,tests=m,M=m,states=3,reports=3,
        instance=f'experiments/results/fake/m{m}_i{i}.toml',instance_hash=f'h-{m}-{i}',
        file_sha256=f'f-{m}-{i}',F_empty_exact='0//1',F_full_exact='1//1')
        for m in range(1,6) for i in range(1,6)]


class AblationPlanTests(unittest.TestCase):
    def setUp(self):
        source=ROOT/'experiments/results/sequential_informative_2026_11'
        output=ROOT/'experiments/results/static_irbb_ablation'
        self.config=B.configuration(source,output)
        self.jobs=B.jobs_for(instances(),self.config)

    def test_factorial_plan(self):
        self.assertEqual(len(self.jobs),200)
        self.assertEqual(len({job['job_id'] for job in self.jobs}),200)
        for m in range(1,6):
            for variant in B.VARIANTS:
                for bound in B.BOUNDS:
                    self.assertEqual(sum(j['tests']==m and j['variant']==variant and
                        j['bound']==bound for j in self.jobs),5)

    def test_scheduler_contract(self):
        self.assertEqual(self.config['hardware']['max_concurrent_jobs'],8)
        self.assertEqual(self.config['parallelism'],
            dict(small_max_jobs=8,medium_max_jobs=8,large_max_jobs=8))
        self.assertEqual(self.config['limits']['time_seconds'],3600.)
        self.assertEqual(self.config['hardware']['global_experiment_ram_gib'],24)
        self.assertEqual(self.config['hardware']['threads_per_job'],1)
        self.assertTrue(self.config['execution']['resume_completed'])
        self.assertFalse(self.config['execution']['run_on_setup'])

    def test_worker_records_requested_statistics(self):
        worker=(HERE/'worker.jl').read_text()
        for field in ('maximum_depth','pruned_by_cost_bound','root_lower_bound',
                      'unreachable_decisions_eliminated','evaluation_cache_hits',
                      'bound_cache_hits','incumbent_updates'):
            # Generic fieldnames(SearchStats) serialization plus the source struct
            # ensures these are not maintained in a second divergent field list.
            self.assertIn(field,(ROOT/'src/core/Interfaces.jl').read_text())
        self.assertIn('fieldnames(SearchStats)',worker)


if __name__=='__main__': unittest.main()
