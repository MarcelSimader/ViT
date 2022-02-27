#! /usr/bin/python

#  Author: Marcel Simader (marcel.simader@jku.at)
#  Date: 18.02.2022
#  (c) Marcel Simader 2022, Johannes Kepler Universität Linz

from typing import Union, List, Optional, Iterator
from io import TextIOBase

import os, sys
import argparse, inspect, pathlib, subprocess, re, shutil, ctypes, glob
import queue, threading, time

#  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#  ~~~~~~~~~~~~~~~~~~~~ GLOBALS ~~~~~~~~~~~~~~~~~~~~
#  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

DESC_STR = r"Scan LaTeX sources for definitions (e.g. '\newcommand')."

OUT_IO = sys.stdout
NUM_THREADS = 8
assert NUM_THREADS > 1
THREAD_TIMEOUT = 0.2

#  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#  ~~~~~~~~~~~~~~~~~~~~ INTERNAL GLOBALS ~~~~~~~~~~~~~~~~~~~~
#  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

File = Union[str, TextIOBase]

#  ~~~~~~~~~~~~~~~~~~~~ OBJECTS ~~~~~~~~~~~~~~~~~~~~

files, messages = queue.Queue(), queue.Queue()

included_files = set()

LOG_FILE_REGEX = re.compile(r"\(([-_/\.\w]+)\nPackage", re.MULTILINE)

LEGAL_FILE_EXTENSIONS = (".tex", ".latex", ".sty", ".cls", ".log",)

#  ~~~~~~~~~~~~~~~~~~~~ CLASSES ~~~~~~~~~~~~~~~~~~~~

class Element:

    prefix = "?Replace the Prefix?"

    def __init__(self, file):
        self.file = norm_class(file)

    def __str__(self) -> str:
        return f"{self.prefix} {self.file}"

class RegexElement(Element):

    comment = re.compile(r"%.*$")

    @classmethod
    def assert_len(cls, obj, length: int) -> None:
        if len(obj) != length:
            err(f"Object '{obj}' is not of expected length '{length}'")
            sys.exit(1)

    @classmethod
    def match(cls, file, text: str) -> Iterator["RegexElement"]:
        for m in re.finditer(cls.regex, text):
            start, stop = m.span()
            # check if there were comments up to now
            if re.search(cls.comment, text[:stop]) is None:
                yield m.groups()

class Command(RegexElement):

    prefix = "command"

    regex = re.compile(r"\\(?:re)?newcommand(?:\*)?" \
        + r"\{([^@#\}\n]+)\}" \
        + r"(?:\[(\d+)\])?", re.MULTILINE)

    def __init__(self, file, name, num_args):
        super().__init__(file)
        self.name = name
        self.num_args = num_args

    @classmethod
    def match(cls, file, text: str) -> Iterator["Command"]:
        for m in super().match(file, text):
            cls.assert_len(m, 2)
            yield Command(file, m[0], 0 if (m[1] is None) else m[1])

    def __str__(self) -> str:
        return f"{super().__str__()} {self.name} {self.num_args}"

class Environment(RegexElement):

    prefix = "environ"

    regex = re.compile(r"\\(?:re)?newenvironment(?:\*)?" \
        + r"\{([^@#\}\n]+)\}", re.MULTILINE)
        # + r"(?:\[(\d+)\])?"

    def __init__(self, file, name):
        super().__init__(file)
        self.name = name

    @classmethod
    def match(cls, file, text: str) -> Iterator["Environment"]:
        for m in super().match(file, text):
            cls.assert_len(m, 1)
            yield Environment(file, m[0])

    def __str__(self) -> str:
        return f"{super().__str__()} {self.name}"

class Include(RegexElement):

    prefix = "include"

    @classmethod
    def include(cls, file) -> Optional["Include"]:
        if file not in included_files:
            return cls(file)

    def __init__(self, file):
        super().__init__(file)
        included_files.add(self.file)

    def __str__(self) -> str:
        return super().__str__()

class IncludeCls(Include):

    regex = re.compile(r"\\documentclass" \
        + r"(?:\[[^@\]\n]+\])?" \
        + r"\{([^@#\}\n]+)\}", re.MULTILINE)

    @classmethod
    def match(cls, file, text: str) -> Iterator[Optional["IncludeCls"]]:
        for m in super().match(file, text):
            cls.assert_len(m, 1)
            yield IncludeCls.include(m[0])

class IncludeSty(Include):

    regex = re.compile(r"\\(?:RequirePackage|usepackage)" \
        + r"(?:\[[^@\]\n]+\])?" \
        + r"\{([^@#\}\n]+)\}", re.MULTILINE)

    @classmethod
    def match(cls, file, text: str) -> Iterator[Optional["IncludeSty"]]:
        for m in super().match(file, text):
            cls.assert_len(m, 1)
            yield IncludeSty.include(m[0])


SCAN_PRIORITY_LIST = (IncludeCls, IncludeSty, Command, Environment,)

#  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#  ~~~~~~~~~~~~~~~~~~~~ FUNCTIONS ~~~~~~~~~~~~~~~~~~~~
#  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

def glob_files(in_files: List[File]) -> None:
    for el in in_files:
        # directly add IOs
        if isinstance(el, TextIOBase):
            files.put(el)
            continue
        # we have a string
        for glob_el in glob.iglob(os.path.expanduser(el), recursive=True):
            if glob_el.endswith(".log"):
                # a latex log file, hopefully
                try:
                    with open(glob_el, "r", encoding="utf-8") as file:
                        scan_log_file(file)
                except UnicodeDecodeError as e:
                    err(f"Failed to decode file '{glob_el}': {e}")
            elif any(glob_el.endswith(ext) for ext in LEGAL_FILE_EXTENSIONS):
                # let file threads deal with extension
                files.put(glob_el)
    for _ in range(NUM_THREADS):
        files.put(None)

def scan_file(io: TextIOBase) -> None:
    text = io.read()
    for cls in SCAN_PRIORITY_LIST:
        for obj in cls.match(io.name, text):
            if obj is not None:
                messages.put(obj)

def scan_log_file(io: TextIOBase) -> None:
    text = io.read()
    for m in re.finditer(LOG_FILE_REGEX, text):
        if m is not None and len(m.groups()) >= 1:
            path, *_ = m.groups()
            files.put(path)

def file_consumer() -> None:
    while True:
        try:
            el = files.get(block=True, timeout=THREAD_TIMEOUT)
            if el is None:
                break
        except Exception:
            break
        try:
            # either pass TextIOBase instance or open a file
            if isinstance(el, TextIOBase):
                scan_file(el)
            else:
                if os.path.isfile(el):
                    with open(el, "r", encoding="utf-8") as file:
                        scan_file(file)
        except UnicodeDecodeError as e:
            err(f"Failed to decode file '{el}': {e}")

def message_consumer() -> None:
    while True:
        try:
            el = messages.get(block=True, timeout=THREAD_TIMEOUT)
            if el is None:
                break
        except Exception:
            break
        OUT_IO.write(f"{str(el)}\n")

#  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#  ~~~~~~~~~~~~~~~~~~~~ UTILS ~~~~~~~~~~~~~~~~~~~~
#  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

def norm_class(path: str) -> str:
    return os.path.basename(path).split(".")[0]

def err(msg: str, end: str="\n") -> None:
    sys.stderr.write(f"{msg}{end}")

#  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#  ~~~~~~~~~~~~~~~~~~~~ MAIN ~~~~~~~~~~~~~~~~~~~~
#  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~


def scan_files(in_files: List[File]) -> None:
    # start up glob thread
    g_thread = threading.Thread(target=glob_files, args=(in_files,))
    g_thread.start()
    # start up file threads
    f_threads = []
    for _ in range(NUM_THREADS - 1):
        f_thread = threading.Thread(target=file_consumer)
        f_thread.start()
        f_threads.append(f_thread)
    # start up message thread
    m_thread = threading.Thread(target=message_consumer)
    m_thread.start()

    # wait for glob thread
    g_thread.join()
    # stop file threads
    for f_thread in f_threads:
        f_thread.join()
    # stop message thread
    messages.put(None)
    m_thread.join()

def main() -> None:
    # args parsing
    parser = argparse.ArgumentParser(description=DESC_STR)
    parser.add_argument(
        "files",
        help="the files to scan. If left blank, will read from stdin instead",
        nargs="*",
        type=str,
    )
    args = parser.parse_args(sys.argv[1:])

    # if no files are given, scan stdin
    if len(args.files) < 1:
        scan_files((sys.stdin,))
    else:
        scan_files(args.files)

if __name__ == "__main__":
    main()

