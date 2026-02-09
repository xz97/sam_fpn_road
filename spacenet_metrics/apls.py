import numpy as np
import os
import argparse
import json

def _resolve_dir(d: str) -> str:
    import os
    # d can be abs (/home/ubuntu/...) or rel (save/save/xxx)
    if os.path.isabs(d):
        return d
    return os.path.join("..", d)


parser = argparse.ArgumentParser()
parser.add_argument('--dir', type=str)

args = parser.parse_args()

apls = []
output_apls = []
name_list = os.listdir(os.path.join(_resolve_dir(args.dir), 'results', 'apls'))
name_list.sort()
for file_name in name_list :
    with open(os.path.join(_resolve_dir(args.dir), 'results', 'apls', f'{file_name}')) as f:
        lines = f.readlines()
    # print(file_name,lines[0].split(' ')[-1])
    # print(lines[0].split(' '))
    if 'NaN' in lines[0]:
        pass
        # apls.append(0)
        # output_apls.append([file_name,0])
    else:
        apls.append(float(lines[0].split(' ')[-1]))
        output_apls.append([file_name,float(lines[0].split(' ')[-1])])

apls_np = np.array(apls, dtype=float)
valid = np.isfinite(apls_np)
print('APLS', float(np.nanmean(apls_np)))
print('APLS_valid', int(valid.sum()), '/', int(len(apls_np)))
with open(f'../{args.dir}/results/apls.json','w') as jf:
    json.dump({'apls':output_apls,'final_APLS':np.mean(apls)},jf)