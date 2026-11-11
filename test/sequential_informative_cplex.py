"""Static campaign-plan checks. These tests never launch Julia or an optimizer."""
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
HERE = ROOT / 'scripts/sequential_informative_cplex'
spec = importlib.util.spec_from_file_location('sequential_informative_static', HERE/'benchmark.py')
B = importlib.util.module_from_spec(spec)
spec.loader.exec_module(B)


def records():
    return [dict(instance_id=f'm{m}_i{i}', id=f'm{m}_i{i}', dataset='sequential_informative',
        profile='generate_oil-informative-v1', seed=10_000*m+i, seed_index=i, tests=m, M=m,
        states=3, reports=3, instance=f'experiments/results/fake/instances/m{m}_i{i}.toml',
        instance_hash=f'instance-{m}-{i}', file_sha256=f'file-{m}-{i}',
        F_empty_exact='0//1', F_full_exact='1//1') for m in range(1, 6) for i in range(1, 6)]


class StaticCampaignTests(unittest.TestCase):
    def setUp(self):
        self.output = ROOT/'experiments/results/fake/execution'
        self.config = B.configuration(self.output.parent, self.output)
        self.jobs = B.jobs_for(records(), self.config)

    def test_exact_campaign_shape(self):
        self.assertEqual(len(self.jobs), 100)
        self.assertEqual(len({job['job_id'] for job in self.jobs}), 100)
        for m in range(1, 6):
            for method in B.METHODS:
                self.assertEqual(sum(j['tests'] == m and j['method'] == method for j in self.jobs), 5)

    def test_phase4_limits_and_no_dimension_exclusions(self):
        self.assertEqual(self.config['limits']['time_seconds'], 3600)
        self.assertEqual(self.config['hardware']['max_concurrent_jobs'], 4)
        self.assertEqual(self.config['parallelism'],
                         dict(small_max_jobs=4, medium_max_jobs=2, large_max_jobs=1))
        self.assertTrue(self.config['execution']['resume_completed'])
        self.assertFalse(self.config['execution']['run_on_setup'])
        self.assertFalse(any('size_guard' in key for job in self.jobs for key in job))

    def test_worker_disables_only_dimension_guards(self):
        support = (HERE/'Support.jl').read_text()
        self.assertIn('unlimited = typemax(Int)', support)
        self.assertIn('dense=true', support)
        self.assertIn('bound=:full_information', support)
        self.assertIn('bound=:legacy_nonsequential', support)
        self.assertIn('max_segments=unlimited', support)
        self.assertIn('max_tests=unlimited', support)
        self.assertIn('max_policy_rows=unlimited', support)

    def test_report_schema_contains_required_metrics(self):
        report = (HERE/'report.py').read_text()
        for field in ('elapsed', 'certified_optimal', 'variables', 'constraints',
                      'irbb_nodes', 'expanded_nodes', 'pruned_nodes', 'policy_evaluations'):
            self.assertIn(field, report)


if __name__ == '__main__':
    unittest.main()
