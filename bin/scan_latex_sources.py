#! /usr/bin/python

#  Author: Marcel Simader (marcel.simader@jku.at)
#  Date: 18.02.2022
#  (c) Marcel Simader 2022, Johannes Kepler Universität Linz

from typing import List, Iterator, Set, Optional, IO

import sys
import os
import pathlib
import re
import threading
from queue import Queue
from multiprocessing import Lock
from multiprocessing.pool import ThreadPool

#  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#  ~~~~~~~~~~~~~~~~~~~~ GLOBALS ~~~~~~~~~~~~~~~~~~~~
#  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

NUM_CONSUMER_THREADS = 4
EXTENSIONS = ("**/*.tex", "**/*.sty", "**/*.cls")

# --log mode regex
LOGMODE_INCLUDE_REGEX = r"(?<=\()(.+)(?=\n\s*(?:Package|Document Class):\s+)"

# types
COMMAND = "command"
ENVIRON = "environ"
INCLUDE = "include"

# regular expressions
_COMM  = r"%.*$"
_OPT   = r"(?:\[[^@\]\n]+\])?"
_CURLS = r"\{([^#@\}\n]+)\}"
_ARGS  = r"(?:\[(\d+)\])?"
NEW_COMMAND = {
    "re": r"\\newcommand"       + _CURLS + _ARGS,
    "type": COMMAND,
}
RENEW_COMMAND = {
    "re": r"\\renewcommand"     + _CURLS + _ARGS,
    "type": COMMAND,
}
NEW_ENV = {
    "re": r"\\newenvironment"   + _CURLS + _ARGS,
    "type": ENVIRON,
}
RENEW_ENV = {
    "re": r"\\renewenvironment" + _CURLS + _ARGS,
    "type": ENVIRON,
}
REQUIRE_PACKAGE = {
    "re": r"\\RequirePackage"   + _OPT + _CURLS,
    "type": INCLUDE,
}
USE_PACKAGE = {
    "re": r"\\usepackage"       + _OPT + _CURLS,
    "type": INCLUDE,
}
DOCUMENTCLASS = {
    "re": r"\\documentclass"    + _OPT + _CURLS,
    "type": INCLUDE,
}
REGEXES = (
    NEW_COMMAND,
    RENEW_COMMAND,
    NEW_ENV,
    RENEW_ENV,
    REQUIRE_PACKAGE,
    USE_PACKAGE,
    DOCUMENTCLASS,
)

# internal constants
CWD = os.path.curdir
END = "END"

#  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#  ~~~~~~~~~~~~~~~~~~~~ UTILS ~~~~~~~~~~~~~~~~~~~~
#  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

def err(msg: str, end = "\n") -> None:
    sys.stderr.write(msg + end)

def norm_path(path: str) -> str:
    return os.path.relpath(os.path.realpath(os.path.normpath(path)), CWD)

def norm_class(path: str) -> str:
    return os.path.basename(path).split(".")[0]

def include_file(
        name: str,
        scanned_files: Set[str],
        scanned_files_lock: Lock,
        resQ: Queue) -> bool:
    with scanned_files_lock:
        if name not in scanned_files:
            scanned_files.add(name)
            resQ.put((
                INCLUDE,
                name
            ))
            return True
        else:
            return False

def file_walk(
        pathlib_path: pathlib.Path,
        path: str,
        scanned_files: Set[str],
        scanned_files_lock: Lock,
        resQ: Queue,
        workQ: Queue) -> Iterator[str]:
    for file in pathlib_path.glob(path):
        class_name = norm_class(file.name)
        if include_file(class_name, scanned_files, scanned_files_lock, resQ):
            workQ.put(str(file))

def scan_file(
        file: IO,
        scanned_files: Set[str],
        scanned_files_lock: Lock,
        resQ: Queue) -> None:
    # read file
    text = file.read()
    for regex in REGEXES:
        re_type, re_re = regex['type'], regex['re']
        for re_match in re.finditer(re_re, text, re.MULTILINE):
            # make sure we are not in a comment
            if re.search(_COMM, text[:re_match.span()[1]]) is not None:
                continue
            # put stuff on result queue
            if re_type is INCLUDE:
                [include_name] = re_match.groups()
                include_file(include_name, scanned_files, scanned_files_lock, resQ)
            elif re_type is COMMAND:
                [command_name, num_args] = re_match.groups()
                resQ.put((
                    COMMAND,
                    norm_class(file.name),
                    command_name,
                    0 if (num_args is None) else num_args,
                ))
            elif re_type is ENVIRON:
                [env_name, num_args] = re_match.groups()
                resQ.put((
                    ENVIRON,
                    norm_class(file.name),
                    env_name,
                    0 if (num_args is None) else num_args,
                ))
            else:
                err(f"Match with unknown type found '{regex['type']}': {re_match}")

def scan_file_producer(
        resQ: Queue,
        scanned_files: Set[str],
        scanned_files_lock: Lock,
        workQ: Queue) -> None:
    el = workQ.get()
    while el is not END:
        try:
            if len(el) < 1:
                scan_file(sys.stdin, scanned_files, scanned_files_lock, resQ)
            else:
                with open(el, "r", encoding="utf-8") as file:
                    scan_file(file, scanned_files, scanned_files_lock, resQ)
        except UnicodeDecodeError as e:
            err(f"Failed to decode file '{el}': {e}")
        finally:
            workQ.task_done()
        el = workQ.get()

def scan_file_consumer(resQ: Queue) -> None:
    el = resQ.get()
    while el is not END:
        sys.stdout.write(" ".join((str(e) for e in el)))
        sys.stdout.write("\n")
        resQ.task_done()
        el = resQ.get()

#  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#  ~~~~~~~~~~~~~~~~~~~~ MAIN ~~~~~~~~~~~~~~~~~~~~
#  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

def main(log_mode: bool, paths: List[str]) -> None:
    # set up queue and thread list
    workQ = Queue()
    resQ = Queue()
    scanned_files = set()
    scanned_files_lock = Lock()
    pro_threads = []
    con_threads = []

    # set up paths for scanning
    if log_mode:
        # get log file from tex path
        log_paths = [(p, p.replace(".tex", ".log")) for p in paths]
        # load files to scan from log file
        work_paths = []
        for tex, log in log_paths:
            if not (tex.endswith(".tex") and log.endswith(".log")):
                err(f"Expected '.tex' file but found '{tex}'")
                sys.exit(1)
            if not os.path.isfile(log):
                err(f"No such file '{log}'")
                sys.exit(1)
            # add this tex file to work_paths as well
            work_paths.append(tex)
            # read file and scan for includes
            with open(log, "r", encoding="utf-8") as f:
                matches = re.findall(LOGMODE_INCLUDE_REGEX, f.read(), re.MULTILINE)
                for match in (m for m in matches if m not in work_paths):
                    work_paths.append(match)
    else:
        work_paths = paths
    work_paths = [norm_path(p) for p in work_paths]

    # start up output
    output = threading.Thread(target=scan_file_consumer, args=(resQ,))
    output.start()

    if len(work_paths) > 0:
        # start up producers
        pathlib_path = pathlib.Path(CWD)
        for path in work_paths:
            if os.path.isdir(path):
                for path_ext in (os.path.join(path, ext) for ext in EXTENSIONS):
                    t = threading.Thread(
                        target=file_walk,
                        args=(
                            pathlib_path,
                            path_ext,
                            scanned_files,
                            scanned_files_lock,
                            resQ,
                            workQ
                        ),
                    )
                    t.start()
                    pro_threads.append(t)
            else:
                t = threading.Thread(
                    target=file_walk,
                    args=(
                        pathlib_path,
                        path,
                        scanned_files,
                        scanned_files_lock,
                        resQ,
                        workQ
                    ),
                )
                t.start()
                pro_threads.append(t)
    else:
        # we only wanna read from stdin it seems
        workQ.put('')

    # start up consumers
    for i in range(NUM_CONSUMER_THREADS):
        t = threading.Thread(
            target=scan_file_producer,
            args=(
                resQ,
                scanned_files,
                scanned_files_lock,
                workQ
            ),
        )
        t.start()
        con_threads.append(t)

    for t in pro_threads:
        t.join()
    for _ in range(NUM_CONSUMER_THREADS):
        workQ.put(END)
    for t in con_threads:
        t.join()
    resQ.put(END)
    output.join()

if __name__ == "__main__":
    if len(sys.argv) <= 1:
        err(f"""
Scan files for LaTeX definitions.
    Usage: {sys.argv[0]} [PATH 1 [PATH 2 [...]]]
        or {sys.argv[0]} --stdin
        or {sys.argv[0]} --log [TEX FILE PATH 1 [TEX FILE PATH 2 [...]]]
        """)
        sys.exit(1)
    else:
        if sys.argv[1].strip().lower() == "--log":
            if len(sys.argv) <= 2:
                err("Missing [TEX FILE PATH [...]].")
                sys.exit(1)
            main(True, sys.argv[2:])
        elif sys.argv[1].strip().lower() == "--stdin":
            main(False, [])
        else:
            main(False, sys.argv[1:])

