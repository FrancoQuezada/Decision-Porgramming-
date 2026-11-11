import importlib.util
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('sequential_cplex_extension',
    ROOT/'scripts/sequential_cplex_extension/benchmark.py')
E=importlib.util.module_from_spec(spec); spec.loader.exec_module(E)


class ExtensionPlanTests(unittest.TestCase):
    def setUp(self):
        self.output=ROOT/'experiments/results/sequential_cplex_extension/test-plan'
        self.chosen=E.selection(); self.config=E.configuration(self.output)
        self.jobs=E.jobs_for(self.chosen,self.config)

    def test_exact_former_guard_set(self):
        self.assertEqual(len(self.jobs),80)
        self.assertEqual(sum(j['method']=='rdp' for j in self.jobs),15)
        self.assertEqual(sum(j['method']=='rjt' for j in self.jobs),15)
        self.assertEqual(sum(j['method'].startswith('irbb') for j in self.jobs),50)

    def test_no_logical_size_guard_remains(self):
        self.assertTrue(all('size_guard_reason' not in j for j in self.jobs))
        self.assertTrue(all(j['size_guard_override'] for j in self.jobs))

    def test_physical_limits_remain(self):
        self.assertEqual(self.config['limits']['time_seconds'],3600.)
        self.assertEqual(self.config['limits']['per_job_memory_gib'],16)
        self.assertEqual(self.config['parallelism']['large_max_jobs'],1)


if __name__=='__main__':
    unittest.main()
