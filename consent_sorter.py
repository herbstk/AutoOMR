#!/usr/bin/env python3
# 2020 Konrad Herbst, <k.herbst@zmbh.uni-heidelberg.de>

import argparse
import warnings

import skimage.io
import skimage.util
import skimage.transform

import os
import sys
import re
import logging
import shutil
import fnmatch

from pyzbar.pyzbar import decode, ZBarSymbol

import matplotlib.pyplot as plt

from joblib import Parallel, delayed

## SETTINGS ##
WORKERS = 4
# outdir set-up
OUTDIR_DIRS = {
    'failed'     : 'processed_failed',
    'done'       : 'processed',
}

BLACK_LEVEL = 0.65
PAGE_EMPTY  = 0.02

def intfn(fn):
    x = re.findall('\d+', fn)
    if len(x) > 0:
        return int(x[-1])
    else:
        return None

# fns needs to be reversely sorted
def disentangle_scans(fns):
    fns_odd = [f for f in fns if intfn(f)%2==1]
    fns_even = [f for f in fns if intfn(f)%2==0]
    fns_doublets = []
    fns_singlets = []
    while len(fns_odd) > 0 and len(fns_even) > 1:
        fno = fns_odd.pop()
        fne = fns_even.pop()
        if intfn(fno) + 1 == intfn(fne):
            fns_doublets.append( (fno, fne) )
        else:
            fns_singlets.append(fne)
            fns_odd.append(fno)
    if len(fns_even) > 0:
        for fne in fns_even:
            fns_singlets.append(fne)
    return (fns_doublets, fns_singlets)

# create a path if not already there
def mkdir(path):
    if not os.path.isdir(path):
        os.mkdir(path)
        return True
    else:
        return False

def load_image(path):
    try:
        image = skimage.io.imread(path, as_gray=True)
    except (OSError, ValueError) as err:
        sleep(1) # maybe image is still written?
        try:
            image = skimage.io.imread(path, as_gray=True)
        except (OSError, ValueError) as err:
            # print('Image "{} could not be loaded...'.format(path))
            return None
    image = skimage.util.img_as_float(image)
    return image

def save_image(image, path):
    with warnings.catch_warnings():
        warnings.simplefilter('ignore', UserWarning)
        image = skimage.util.img_as_ubyte(image)
    if os.path.exists(path):
        path = os.path.splitext(path)
        path = '{}-1{}'.format(path[0], path[1])
    skimage.io.imsave(path, image)

def save_incr_image(image, path):
    path, fn = os.path.split(path)
    base, ext = os.path.splitext(fn)
    i = 1
    while True:
        nfn = '{}-{:0=2d}{}'.format(base, i, ext)
        npath = os.path.join(path, nfn)
        if not os.path.exists(npath):
            save_image(image, npath)
            return npath
        i = i + 1

def fill(image):
    return (image < BLACK_LEVEL).sum() / (image.shape[0] * image.shape[1])

def crop_region(im, reg):
    w, h, x, y = reg
    return im[y:y+h, x:x+w]

def extract_barcode(image, reg = None):
    if reg is not None:
        image = crop_region(image, reg)
    barcode = decode(image  * 255, [ZBarSymbol.CODE128])
    return barcode

def process_doublepage(file1, file2, outdirs, debug):
    log1 = ['Log for page1 "{}" (page2: {})'.format(file1, file2)]
    log2 = ['Log for page2 "{}" (page1: {})'.format(file2, file1)]
    page1 = load_image(file1)
    page2 = load_image(file2)
    if fill(page1) > PAGE_EMPTY:
        bc = extract_barcode(page1)
        # if no bc found swap page1/2 and try extracting bc again
        if len(bc) == 0:
            file2, file1 = file1, file2
            page2, page1 = page1, page2
            bc = extract_barcode(page1)
        if len(bc) == 1:
            id = bc[0].data.decode('ASCII')
            # if bc is on the left side of the image, rotate 180°
            side = bc[0].rect.left / page1.shape[1]
            if side <= 0.5:
                page1 = skimage.transform.rotate(page1,  180)
                page2 = skimage.transform.rotate(page2,  180)
                # write out page1 and page2
            outdir = os.path.join(outdirs['done'], id)
            mkdir(outdir)
            outfile = '{}.png'.format(id)
            outfile1 = save_incr_image(page1, os.path.join(outdir, outfile))
            log1.append('Save page1 "{}" as "{}" ...'.format(file1, outfile1))
            if debug:
                with open(os.path.splitext(outfile1)[0] + '-log.txt', 'w') as f:
                    f.write('\n'.join(log1))
            ## handle empty 2nd pages
            if fill(page2) > PAGE_EMPTY:
                outfile2 = save_incr_image(page2, os.path.join(outdir, outfile))
                log2.append('Save page2 "{}" as "{}" ...'.format(file2, outfile2))
                if debug:
                    with open(os.path.splitext(outfile2)[0] + '-log.txt', 'w') as f:
                           f.write('\n'.join(log2))
            else:
                shutil.copy2(file2, outdirs['failed'])
                log2.append('Page2 "{}" was detected as empty and therefore copied to "{}" ...'.format(file2, outdirs['failed']))
                if debug:
                    with open(os.path.join(outdirs['failed'], os.path.basename(os.path.splitext(file2)[0])) + '-log.txt', 'w') as f:
                        f.write('\n'.join(log2))
        else:
            ## no (or too many) bc found on both pages
            shutil.copy2(file1, outdirs['failed'])
            shutil.copy2(file2, outdirs['failed'])
            log1.append('Copied file "{}" to "{}" ...'.format(file1, outdirs['failed']))
            log2.append('Copied file "{}" to "{}" ...'.format(file2, outdirs['failed']))
            if debug:
                with open(os.path.join(outdirs['failed'], os.path.basename(os.path.splitext(file1)[0])) + '-log.txt', 'w') as f:
                    f.write('\n'.join(log1))
                with open(os.path.join(outdirs['failed'], os.path.basename(os.path.splitext(file2)[0])) + '-log.txt', 'w') as f:
                    f.write('\n'.join(log2))
    else:
        bc = extract_barcode(page2)
        if len(bc) == 1:
            id = bc[0].data.decode('ASCII')
            # if bc is on the left side of the image, rotate 180°
            side = bc[0].rect.left / page1.shape[1]
            if side <= 0.5:
                page2 = skimage.transform.rotate(page2,  180)
                ## save page2 and move page1 to failed
            outdir = os.path.join(outdirs['done'], id)
            mkdir(outdir)
            shutil.copy2(file1, outdirs['failed'])
            log1.append('Page1 "{}" was detected as empty and therefore copied to "{}" ...'.format(file1, outdirs['failed']))
            if debug:
                with open(os.path.join(outdirs['failed'], os.path.basename(os.path.splitext(file1)[0])) + '-log.txt', 'w') as f:
                    f.write('\n'.join(log1))
            outfile = '{}.png'.format(id)
            outfile2 = save_incr_image(page2, os.path.join(outdir, outfile))
            log2.append('Save page2 "{}" as "{}" ...'.format(file2, outfile2))
            if debug:
                with open(os.path.splitext(outfile2)[0] + '-log.txt', 'w') as f:
                    f.write('\n'.join(log2))
        else:
            ## no bc found on both pages
            shutil.copy2(file1, outdirs['failed'])
            shutil.copy2(file2, outdirs['failed'])
            log1.append('Copied file "{}" to "{}" ...'.format(file1, outdirs['failed']))
            log2.append('Copied file "{}" to "{}" ...'.format(file2, outdirs['failed']))
            if debug:
                with open(os.path.join(outdirs['failed'], os.path.basename(os.path.splitext(file1)[0])) + '-log.txt', 'w') as f:
                    f.write('\n'.join(log1))
                with open(os.path.join(outdirs['failed'], os.path.basename(os.path.splitext(file2)[0])) + '-log.txt', 'w') as f:
                    f.write('\n'.join(log2))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('indir', help = 'input directory')
    ap.add_argument('outdir', help = 'output directory')
    ap.add_argument('-d', dest='debug', action='store_true', help='Debug mode')
    ap.add_argument('-v', dest='verbose', action='count', default=0, help='Increase verbosity')
    args = ap.parse_args()

    levels = (logging.WARNING, logging.INFO, logging.DEBUG)
    logging.basicConfig(level=levels[min(len(levels)-1, args.verbose)])

    # prepare output directory
    ## if output_dir already exists throw a warning and stop
    if not mkdir(args.outdir) and len(os.listdir(args.outdir)) > 0:
        logging.info('The outdir already exists and is not empty. Please clear manually or provide a different outdir.')
        return 1
    outdirs = dict()
    for k, v in OUTDIR_DIRS.items():
        outdirs[k] = os.path.join(args.outdir, v)
        mkdir(outdirs[k])

    ## acquire scans to process from subdirectories of current directory (if none found we might not be in the right directory??)
    with os.scandir(indir) as it:
        files = [f.name for f in os.scandir() if f.is_file() and not f.name.startswith('.') and f.name.endswith('.pnm')]
        logging.info('Found {} pnm-files in current working directory.'.format(len(files)))
        files.sort(reverse = True)
        files_doublets, files_singlets = disentangle_scans(files)
        logging.info('Detected {} double and {} single pages.'.format(len(files_doublets), len(files_singlets)))
        ## iterate over doublet files and figure out what they are
        if WORKERS == 1:
            # non-paralleled processing
            logs = [process_doublepage(file1, file2, outdirs, args.debug) for file1, file2 in files_doublets]
        else:
            Parallel(n_jobs = WORKERS)(delayed(process_doublepage)(file1, file2, outdirs, args.debug) for file1, file2 in files_doublets)

        ## cp singlet files to failed
        for fs in files_singlets:
            log = ['Log for single page "{}"'.format(fs)]
            log.append('Copied file "{}" to "{}" ...'.format(fs, outdirs['failed']))
            shutil.copy2(fs, outdirs['failed'])
            if args.debug:
                with open(os.path.join(outdirs['failed'], os.path.basename(os.path.splitext(fs)[0])) + '-log.txt', 'w') as f:
                    f.write('\n'.join(log))

if __name__ == '__main__':
    sys.exit(main())
