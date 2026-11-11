"""Generate saved-result CSV, Markdown and LaTeX tables; never imports an optimizer."""
import argparse
import csv
from datetime import datetime, timezone
import importlib.util
import json
from pathlib import Path
import statistics

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('sequential_informative_benchmark', HERE/'benchmark.py')
B = importlib.util.module_from_spec(spec)
spec.loader.exec_module(B)


def write_csv(path, rows):
    columns = list(dict.fromkeys(key for row in rows for key in row))
    with path.open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=columns)
        writer.writeheader()
        for row in rows:
            writer.writerow({key: json.dumps(value, sort_keys=True) if isinstance(value, (dict, list)) else value
                             for key, value in row.items()})


def mean(rows, field):
    values = [row[field] for row in rows if isinstance(row.get(field), (int, float))]
    return statistics.mean(values) if values else None


def aggregate(records):
    result = []
    for m in range(1, 6):
        for method in B.METHODS:
            group = [row for row in records if row['tests'] == m and row['method'] == method]
            attempted = [row for row in group if row.get('attempted')]
            optimal = [row for row in group if row.get('certified_optimal')]
            row = dict(M=m, method=method, planned=len(group), attempted=len(attempted),
                optimal=len(optimal), feasible=sum(bool(r.get('policy_complete')) for r in group),
                time_limits=sum(r['status'] == 'TIME_LIMIT' for r in group),
                memory_stops=sum('MEMORY' in r['status'] or r['status'] == 'OUT_OF_MEMORY' for r in group),
                errors=sum(r['status'] in ('ERROR', 'WORKER_EXIT', 'INITIALIZATION_TIMEOUT',
                                           'VALIDATION_TIMEOUT') for r in group),
                interrupted=sum(r['status'] == 'INTERRUPTED' for r in group),
                not_run=sum(r['status'] == 'NOT_RUN' for r in group),
                mean_observed_runtime=mean(attempted, 'elapsed'),
                mean_optimal_runtime=mean(optimal, 'elapsed'),
                mean_solver_runtime=mean(optimal, 'solver_seconds'),
                mean_preprocessing_runtime=mean(optimal, 'preprocessing_seconds'),
                mean_construction_runtime=mean(optimal, 'construction_seconds'),
                mean_optimization_runtime=mean(optimal, 'optimization_seconds'),
                mean_variables=mean(attempted, 'variables'),
                mean_constraints=mean(attempted, 'constraints'),
                mean_irbb_nodes=mean(attempted, 'irbb_nodes'),
                mean_expanded_nodes=mean(attempted, 'expanded_nodes'),
                mean_pruned_nodes=mean(attempted, 'pruned_nodes'),
                mean_policy_evaluations=mean(attempted, 'policy_evaluations'),
                mean_cache_hits=mean(attempted, 'cache_hits'),
                mean_cache_misses=mean(attempted, 'cache_misses'),
                mean_bound_seconds=mean(attempted, 'bound_seconds'),
                mean_evaluation_seconds=mean(attempted, 'evaluation_seconds'))
            result.append(row)
    return result


def fmt(value):
    return '--' if value is None else f'{value:.6g}'


def render_markdown(rows):
    by_key = {(row['M'], row['method']): row for row in rows}
    lines = [
        '# Sequential informative Oil Wildcatter benchmark', '',
        'Each cell is `observed mean wall time; certified/feasible; dimensions or IR-B&B nodes`.',
        'Means use saved attempted runs; `--` denotes unavailable data. Validation time is reported separately in CSV.', '',
        '| M | Dense RDP | Sequential RJT | IR-B&B full information | IR-B&B legacy |',
        '| --- | --- | --- | --- | --- |',
    ]
    for m in range(1, 6):
        cells = []
        for method in B.METHODS:
            row = by_key[m, method]
            suffix = (f"v/c={fmt(row['mean_variables'])}/{fmt(row['mean_constraints'])}"
                      if method in ('rdp', 'rjt') else f"nodes={fmt(row['mean_irbb_nodes'])}")
            cells.append(f"{fmt(row['mean_observed_runtime'])} s; {row['optimal']}/{row['feasible']}; {suffix}")
        lines.append('| ' + str(m) + ' | ' + ' | '.join(cells) + ' |')
    lines += ['', 'Statuses, exact policy values, bounds, gaps, solver timing, model dimensions, memory diagnostics,',
              'and complete IR-B&B search/cache statistics are retained in `per_instance.csv` and `aggregated.csv`.']
    return '\n'.join(lines) + '\n'


def render_latex(rows):
    by_key = {(row['M'], row['method']): row for row in rows}
    lines = [r'\begin{tabular}{r|rrr|rrr|rr|rr}', r'\hline',
        r'$M$ & \multicolumn{3}{c|}{Dense RDP} & \multicolumn{3}{c|}{Sequential RJT} & \multicolumn{2}{c|}{IRBB FI} & \multicolumn{2}{c}{IRBB legacy} \\',
        r' & $t$ & O/F & v/c & $t$ & O/F & v/c & $t$ & O/F & $t$ & O/F \\', r'\hline']
    for m in range(1, 6):
        cells = [str(m)]
        for method in B.METHODS:
            row = by_key[m, method]
            cells += [fmt(row['mean_observed_runtime']), f"{row['optimal']}/{row['feasible']}"]
            if method in ('rdp', 'rjt'):
                cells.append(f"{fmt(row['mean_variables'])}/{fmt(row['mean_constraints'])}")
        lines.append(' & '.join(cells) + r' \\')
    lines += [r'\hline', r'\end{tabular}']
    return '\n'.join(lines) + '\n'


def report(campaign):
    output, c, chosen, jobs = B.load_prepared(campaign)
    current = B.current_protocol(c, chosen)
    baseline = json.loads((output/'protocol.json').read_text())
    if baseline['scientific'] != current['scientific']:
        raise ValueError('scientific source, input or configuration changed since prepare')
    saved = B.scheduler.read_results(output)
    records = [saved.get(job['job_id'], dict(job, status='NOT_RUN', attempted=False,
        certified_optimal=False, policy_complete=False)) for job in jobs]
    aggregates = aggregate(records)
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    destination = output/'reports'/stamp
    destination.mkdir(parents=True)
    write_csv(destination/'per_instance.csv', records)
    write_csv(destination/'aggregated.csv', aggregates)
    (destination/'comparison.md').write_text(render_markdown(aggregates))
    (destination/'comparison.tex').write_text(render_latex(aggregates))
    print(destination)
    return destination


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('campaign', type=Path)
    report(parser.parse_args().campaign)
