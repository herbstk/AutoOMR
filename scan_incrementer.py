#!/usr/bin/env python3
# 2020 Konrad Herbst, <k.herbst@zmbh.uni-heidelberg.de>

import argparse
import os
import sys
import shutil
import re

def intfn(fn):
    x = re.findall('\d+', fn)
    if len(x) > 0:
        return int(x[-1])
    else:
        return None

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('indir', help = 'input directory')
    args = ap.parse_args()

    with os.scandir(args.indir) as it:
        files = [f.path for f in it if f.is_file() and not f.name.startswith('.') and f.name.endswith('.pnm')]

    print('Found {} pnm-files in current working directory.'.format(len(files)))
    files.sort(reverse = True)

    for f in files:
        nf = 'image-{:0=4d}.pnm'.format(intfn(f)+1)
        nf = os.path.join(args.indir, nf)
        print('Move {} to {}'.format(f, nf))
        shutil.move(f, nf)

if __name__ == '__main__':
    sys.exit(main())
