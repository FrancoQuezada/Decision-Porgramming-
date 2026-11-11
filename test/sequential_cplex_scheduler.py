"""Optimization-free adapter tests. CPLEX checks live in the locked Julia env."""
import importlib.util
from pathlib import Path
import unittest

HERE=Path(__file__).resolve().parents[1]/'scripts/sequential_cplex'
def load(name,file):
    spec=importlib.util.spec_from_file_location(name,HERE/file)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
B=load('sequential_adapter_test','benchmark.py')
R=load('sequential_report_test','report.py')


class SequentialAdapterTests(unittest.TestCase):
    def test_original_guards_are_retained(self):
        self.assertIsNone(B.size_guard('rdp',5))
        self.assertIn('524288',B.size_guard('rdp',6))
        self.assertIsNone(B.size_guard('rjt',5))
        self.assertIn('RJT_TEST_GUARD',B.size_guard('rjt',6))
        self.assertIsNone(B.size_guard('irbb_fi',3))
        self.assertIn('85',B.size_guard('irbb_fi',4))

    def test_sample_is_exactly_five_archived_inputs_per_size(self):
        selected=B.selection()
        self.assertEqual(len(selected),40)
        for m in range(1,9):
            self.assertEqual(sorted(r['seed_id'] for r in selected if r['M']==m),[1,2,3,4,5])

    def test_scheduler_reuse_and_unique_jobs(self):
        config=B.configuration(B.ROOT/'experiments/results/test-only-not-created')
        jobs=B.jobs_for(B.selection(),config)
        self.assertEqual(len(jobs),160)
        self.assertEqual(len({j['job_id'] for j in jobs}),160)
        self.assertEqual(sum('size_guard_reason' in j for j in jobs),80)
        self.assertEqual(config['limits']['time_seconds'],3600.)
        self.assertEqual(config['hardware']['threads_per_job'],1)

    def test_means_exclude_timeout_and_invalid_certificates(self):
        rows=[dict(tests=1,method='rdp',status='OPTIMAL',attempted=True,certified_optimal=True,policy_complete=True,elapsed=2.,solver_seconds=1.),
            dict(tests=1,method='rdp',status='TIME_LIMIT',attempted=True,certified_optimal=False,policy_complete=True,elapsed=3600.)]
        row=next(r for r in R.aggregate(rows) if r['M']==1 and r['method']=='rdp')
        self.assertEqual(row['mean_total'],2.)
        self.assertEqual((row['optimal'],row['feasible'],row['time_limits']),(1,2,1))
        self.assertEqual(row['mean_solver'],1.)


if __name__=='__main__':
    unittest.main()
