"""Saved-record-only CSV, Markdown and LaTeX reporting for the IR-B&B ablation."""
import argparse, csv, importlib.util, json, statistics
from datetime import datetime, timezone
from pathlib import Path

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('irbb_ablation_benchmark',HERE/'benchmark.py')
B=importlib.util.module_from_spec(spec); spec.loader.exec_module(B)


def write_csv(path,rows):
    fields=list(dict.fromkeys(k for row in rows for k in row))
    with path.open('w',newline='') as stream:
        writer=csv.DictWriter(stream,fieldnames=fields); writer.writeheader()
        for row in rows: writer.writerow({k:json.dumps(v,sort_keys=True) if isinstance(v,(dict,list)) else v for k,v in row.items()})


def mean(rows,key):
    values=[r[key] for r in rows if isinstance(r.get(key),(int,float))]
    return statistics.mean(values) if values else None


def mean_runtime(rows):
    values=[r['elapsed'] if r.get('elapsed') is not None else r.get('elapsed_censored_seconds')
            for r in rows]
    values=[value for value in values if isinstance(value,(int,float))]
    return statistics.mean(values) if values else None


def aggregate(records):
    rows=[]
    for m in range(1,6):
        for variant in B.VARIANTS:
            for bound in B.BOUNDS:
                group=[r for r in records if r['tests']==m and r['variant']==variant and r['bound']==bound]
                attempted=[r for r in group if r.get('attempted')]
                rows.append(dict(M=m,variant=variant,bound=bound,planned=len(group),attempted=len(attempted),
                    optimal=sum(bool(r.get('certified_optimal')) for r in group),
                    feasible=sum(bool(r.get('policy_complete')) for r in group),
                    time_limits=sum(r['status']=='TIME_LIMIT' for r in group),
                    errors=sum(r['status'] in ('ERROR','WORKER_EXIT','VALIDATION_TIMEOUT') for r in group),
                    mean_time=mean_runtime(attempted),mean_nodes=mean(attempted,'visited'),
                    mean_pruned=mean(attempted,'pruned'),mean_bound_time=mean(attempted,'bound_time'),
                    mean_evaluation_time=mean(attempted,'evaluation_time'),
                    mean_unreachable_eliminated=mean(attempted,'unreachable_decisions_eliminated'),
                    mean_evaluation_cache_hits=mean(attempted,'evaluation_cache_hits'),
                    mean_bound_cache_hits=mean(attempted,'bound_cache_hits')))
    return rows


def text(value): return '--' if value is None else f'{value:.6g}'


def report(output):
    output=output.resolve(); c,chosen,jobs=B.load(output)
    current=B.current_protocol(c,chosen); baseline=json.loads((output/'protocol.json').read_text())
    if baseline['scientific']!=current['scientific']: raise ValueError('scientific protocol changed')
    saved=B.scheduler.read_results(output)
    records=[saved.get(job['job_id'],dict(job,status='NOT_RUN',attempted=False,
        certified_optimal=False,policy_complete=False)) for job in jobs]
    aggregates=aggregate(records)
    destination=output/'reports'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    destination.mkdir(parents=True)
    write_csv(destination/'detailed.csv',records); write_csv(destination/'aggregated.csv',aggregates)
    columns=['M','Instance','Variant','Bound','Time','Nodes','Pruned','Bound time','Evaluation time','Status']
    lines=['# Sequential IR-B&B ablation','', '| '+' | '.join(columns)+' |','|'+'|'.join(['---']*len(columns))+'|']
    for row in records:
        lines.append('| '+' | '.join((str(row['tests']),row['instance_id'],row['variant'],row['bound'],
            text(row.get('elapsed') or row.get('elapsed_censored_seconds')),text(row.get('visited')),
            text(row.get('pruned')),text(row.get('bound_time')),text(row.get('evaluation_time')),row['status']))+' |')
    (destination/'comparison.md').write_text('\n'.join(lines)+'\n')
    latex=[r'\begin{tabular}{rrlllrrrrl}',r'\hline',
        r'$M$ & Instance & Variant & Bound & Time & Nodes & Pruned & $t_b$ & $t_e$ & Status \\',r'\hline']
    for row in records:
        latex.append(' & '.join((str(row['tests']),row['instance_id'].replace('_',r'\_'),row['variant'].replace('_',r'\_'),
            row['bound'].replace('_',r'\_'),text(row.get('elapsed') or row.get('elapsed_censored_seconds')),
            text(row.get('visited')),text(row.get('pruned')),text(row.get('bound_time')),
            text(row.get('evaluation_time')),row['status'].replace('_',r'\_')))+r' \\')
    latex += [r'\hline',r'\end{tabular}']; (destination/'comparison.tex').write_text('\n'.join(latex)+'\n')
    print(destination); return destination


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument('output',type=Path)
    report(parser.parse_args().output)
