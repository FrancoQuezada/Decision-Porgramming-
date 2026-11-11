"""Saved-record reporting only; never calls an optimizer or changes raw results."""
import argparse
import csv
from datetime import datetime, timezone
import importlib.util
import json
from pathlib import Path
import statistics

spec = importlib.util.spec_from_file_location('sequential_cplex_benchmark', Path(__file__).with_name('benchmark.py'))
B = importlib.util.module_from_spec(spec)
spec.loader.exec_module(B)


def write_csv(path, rows):
    columns = list(dict.fromkeys(k for r in rows for k in r))
    with path.open('w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=columns)
        w.writeheader()
        for r in rows:
            w.writerow({k: json.dumps(v, sort_keys=True) if isinstance(v, (dict,list)) else v for k,v in r.items()})


def aggregate(records):
    result = []
    for m in range(1,9):
        for method in B.METHODS:
            group = [r for r in records if r['tests'] == m and r['method'] == method]
            optimal = [r for r in group if r.get('certified_optimal')]
            row = dict(M=m, method=method, planned=5,
                attempted=sum(bool(r.get('attempted')) for r in group),
                optimal=len(optimal), feasible=sum(bool(r.get('policy_complete')) for r in group),
                time_limits=sum(r['status']=='TIME_LIMIT' for r in group),
                memory_failures=sum('MEMORY' in r['status'] or r['status']=='OUT_OF_MEMORY' for r in group),
                size_guards=sum(r['status']=='SKIPPED_SIZE_GUARD' for r in group),
                not_run=sum(r['status']=='NOT_RUN' for r in group),
                errors=sum(r['status'] in ('ERROR','WORKER_EXIT','INITIALIZATION_TIMEOUT','VALIDATION_TIMEOUT') for r in group))
            for source, target in [('elapsed','mean_total'),('solver_seconds','mean_solver'),
                    ('preprocessing_seconds','mean_preprocessing'),('construction_seconds','mean_construction'),
                    ('optimization_seconds','mean_optimization'),('irbb_nodes','mean_nodes'),
                    ('expanded_nodes','mean_expanded'),('pruned_nodes','mean_pruned'),
                    ('policy_evaluations','mean_policy_evaluations'),('bound_seconds','mean_bound_seconds'),
                    ('evaluation_seconds','mean_evaluation_seconds'),('cache_hits','mean_cache_hits'),('cache_misses','mean_cache_misses')]:
                values = [r[source] for r in optimal if r.get(source) is not None]
                if values:
                    row[target] = statistics.mean(values)
            for key in ('variables','constraints'):
                values = {r[key] for r in group if r.get(key) is not None}
                if len(values)==1:
                    row[key] = values.pop()
            result.append(row)
    return result


def report(output):
    config = json.loads((output/'configuration.json').read_text())
    chosen = json.loads((output/'selection.json').read_text())
    # Same source/input fingerprint checks as execution, without launching work.
    current = B.current_protocol(config, chosen)
    baseline = json.loads((output/'protocol.json').read_text())
    if baseline['scientific'] != current['scientific']:
        raise ValueError('Scientific source/configuration changed since the campaign')
    saved = B.scheduler.read_results(output)
    records = []
    for job in json.loads((output/'plan.json').read_text()):
        records.append(saved.get(job['job_id'],dict(job,status='NOT_RUN',attempted=False,
            certified_optimal=False,policy_complete=False)))
    aggregates = aggregate(records)
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    dest = output/'reports'/stamp
    dest.mkdir(parents=True)
    write_csv(dest/'per_instance.csv',records)
    write_csv(dest/'aggregated.csv',aggregates)
    pairs=[]
    for r in chosen:
        a=saved.get(r['id']+'__rdp',{}); b=saved.get(r['id']+'__rjt',{})
        pair=dict(instance_id=r['id'],M=r['M'],index=r['seed_id'],instance_hash=r['instance_sha256'],
            both_certified=bool(a.get('certified_optimal') and b.get('certified_optimal')))
        if a.get('policy_complete') and b.get('policy_complete'):
            pair.update(rdp_physical=a['policy_value'],rjt_physical=b['policy_value'],
                exact_physical_agreement=a['policy_value_exact']==b['policy_value_exact'])
        pairs.append(pair)
    write_csv(dest/'rdp_rjt_pairs.csv',pairs)
    reference = (output/'published_gurobi_reference.csv').read_bytes()
    (dest/'published_gurobi_reference.csv').write_bytes(reference)
    def number(value):
        return f'{value:.6g}' if value is not None else '—'
    def cell(r):
        if r['size_guards']==5:
            return 'GUARD; 0/0'
        if not r['attempted']:
            return 'NOT_RUN; 0/0'
        text=number(r.get('mean_total'))+' s'
        if r['method'] in ('rdp','rjt'):
            text+='; solver='+number(r.get('mean_solver'))+' s'
            text+=f"; {r['optimal']}/{r['feasible']}; c/v={r.get('constraints','—')}/{r.get('variables','—')}"
        else:
            text+=f"; {r['optimal']}/{r['feasible']}; nodes="+number(r.get('mean_nodes'))
        if r['time_limits'] or r['memory_failures'] or r['errors']:
            text+=f"; T={r['time_limits']}, Mem={r['memory_failures']}, E={r['errors']}"
        return text
    bykey={(r['M'],r['method']):r for r in aggregates}
    lines=['# Sequential Oil — our CPLEX baseline, five instances per size','',
        'CPLEX 22.1.1; Phase-4 CPLEX-Default; archived indices 1–5; dense RDP and unchanged RJT/IR-B&B.',
        'Means use certified optimal runs only. O/F counts usable physical policies, including time-limited policies in F.',
        'Measured totals follow Phase 4: preparation, optimization and method recovery; independent validation is separate.',
        'These are single observed timings, not published Gurobi reproductions or evidence of general superiority. RR% is deferred.','',
        '| M | RDP | RJT | IR-B&B FI | IR-B&B Legacy |',
        '| --- | --- | --- | --- | --- |']
    for m in range(1,9):
        lines.append('| '+str(m)+' | '+' | '.join(cell(bykey[(m,method)]) for method in B.METHODS)+' |')
    lines+=['','c/v = actual constraints/variables; GUARD = existing size safeguard, never attempted; missing means stay missing.',
        'Raw statuses, bounds, gaps, exact policy values, input hashes, search/cache statistics and memory diagnostics are retained in CSV/JSON.',
        'Published Table 3 is retained separately in published_gurobi_reference.csv and is never merged into CPLEX observations.']
    (dest/'comparison.md').write_text('\n'.join(lines)+'\n')
    latex=[r'\begin{tabular}{r|rrl|rrl|rl|rl}',r'\hline',
        r'$M$ & \multicolumn{3}{c|}{RDP} & \multicolumn{3}{c|}{RJT} & \multicolumn{2}{c|}{IRBB FI} & \multicolumn{2}{c}{IRBB Legacy} \\',
        r' & $\bar t$ & $\bar t_s$ & O/F & $\bar t$ & $\bar t_s$ & O/F & $\bar t$ & O/F & $\bar t$ & O/F \\',r'\hline']
    for m in range(1,9):
        cells=[str(m)]
        for method in B.METHODS:
            r=bykey[(m,method)]
            cells.append(f"{r['mean_total']:.6g}" if 'mean_total' in r else '--')
            if method in ('rdp','rjt'):
                cells.append(f"{r['mean_solver']:.6g}" if 'mean_solver' in r else '--')
            cells.append(f"{r['optimal']}/{r['feasible']}")
        latex.append(' & '.join(cells)+r' \\')
    latex += [r'\hline',r'\end{tabular}']
    (dest/'comparison.tex').write_text('\n'.join(latex)+'\n')
    print(dest)
    return dest


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('output',type=Path)
    report(p.parse_args().output.resolve())
