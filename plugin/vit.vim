" Functions for the ViT plugin that are only loaded once.
" Author: Marcel Simader (marcel0simader@gmail.com)
" Date: 26.12.2021
" (c) Marcel Simader 2021

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ DEBUG ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

if !exists('*s:LoadViT')
    function! s:LoadViT()
        if &ft != 'latex'
            return
        endif
        let buf = bufname()
        unlet g:vit_did_plugin g:vit_did_ftdetect
        call setbufvar(buf, 'current_syntax', 0)
        call setbufvar(buf, 'did_ftplugin', 0)
        " reload scripts
        let start = reltime()
        for file in ['ftdetect/latex.vim', 'ftplugin/latex.vim', 'plugin/vit.vim',
                    \ 'syntax/latex.vim', 'user/*.vim']
            execute 'runtime '.file
        endfor
        echohl StatusLineTerm
        echomsg 'Loading ViT took '
                    \ .string(reltimefloat(reltime(start)) * 1000.0)
                    \ .'ms'
        echohl None
    endfunction
    command ViTLoadLocal :call <SID>LoadViT()
endif

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ /DEBUG ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

" acts as include guard
if exists('g:vit_did_plugin') || (exists('g:vit_enable') && !g:vit_enable)
    finish
endif
let g:vit_did_plugin = 1

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ GLOBAL CONFIGS ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

" Adds a new ViT global config option. This only defines the
" vars once, and makes sure user wishes are granted. Merry Christmas.
" It also sets an optional default value if the assignment failed with
" the initially requested value.
function s:Config(name, value, default = v:none)
    try
        if !exists(a:name) | let {a:name} = a:value() | endif
    catch
        echohl WarningMsg
        echomsg 'ViT Warning: Problem while processing "'.a:name.'" ('.v:exception.')'
        echohl None
        let {a:name} = a:default
    endtry
endfunction

call s:Config('g:vit_enable', {-> 1})
if !g:vit_enable | finish | endif
call s:Config('g:vit_enable_keybinds', {-> 1})
call s:Config('g:vit_enable_commands', {-> 1})
call s:Config('g:vit_leader', {-> '<C-@>'})
call s:Config('g:vit_compiler', {-> {
	    \ 'compiler': 'pdflatex',
	    \ 'flags': '-interaction=nonstopmode -file-line-error %',
            \ 'errregex': '^\s*\(.\{-}\)\s*:\s*\(\d\+\)\s*:\s*\(.\{-}\)\s*$',
	    \ 'numcomps': 1,
            \ }})
call s:Config('g:vit_max_errors', {-> 10})
call s:Config('g:vit_jump_chars', {-> [' ', '(', '[', '{']})
call s:Config('g:vit_template_remove_on_abort', {-> 1})
call s:Config('g:vit_comment_line', {-> '% '.repeat('~', 70)})
call s:Config('g:vit_autosurround_chars', {->
            \ [['(', ')'], ['[', ']'], ['{', '}'], ['$', '$']]})
call s:Config('g:vit_compile_on_write', {-> 0})

" TODO: maybe document this
call s:Config('g:vit_signs', {-> {}})
call s:Config('g:vit_num_errors', {-> 0})
call s:Config('g:vit_is_compiling', {-> 0})
call s:Config('g:vit_compilation_queued', {-> 0})

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ SIGNS ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

highlight ViTErrorSign ctermfg=White ctermbg=DarkRed
call sign_define('ViTError', #{text: '!>', texthl: 'ViTErrorSign'})

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ COMPILING ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

" Compiles the contents of a file using the configured LaTeX compiler.
" Arguments:
"   buf, the buffer to take settings from to figure out what to compile
"   [silent,] can be '!' to be executed as background job, otherwise
"       open a new terminal window, defaults to ''
"   [compiler,] compiler dict described in ':h g:vit_compiler', defaults to {},
"       each key that is not set is set to the value of b:vit_compiler, which is initially
"       set to the global value g:vit_compiler
"   [pwd,] manually sets the working path, defaults to current working directory
"   [currentcomp,] need not be set by user, internal argument, defaults to v:none
function vit#Compile(buf, silent = '', compiler = {}, pwd = v:none,
            \ currentcomp = v:none)
    " parse modline if this is our first call, just in case it changed
    if a:currentcomp is v:none
        call vit#ParseModeline(a:buf)
    endif
    " set up variables
    let pwd = (a:pwd is v:none) ? getcwd() : a:pwd
    let currentcomp = (a:currentcomp is v:none) ? 1 : a:currentcomp
    let filepath = vit#GetRootFile(a:buf)
    let firstcall = a:currentcomp is v:none

    " get from arguments first, then global value, finally resort to v:none
    let cdict = {}
    function! SetDictITE(key) closure
        let cdict[a:key] = get(a:compiler, a:key,
                    \ get(s:GetVar(a:buf, 'vit_compiler'), a:key, v:none))
    endfunction
    call SetDictITE('compiler')
    call SetDictITE('flags')
    call SetDictITE('errregex')
    call SetDictITE('numcomps')

    " make sure compiler is complete
    if cdict['compiler'] is v:none || cdict['flags'] is v:none
                \ || cdict['errregex'] is v:none || cdict['numcomps'] is v:none
        echohl ErrorMsg
        echomsg 'ViT compiler dictionary '.string(cdict).' is incomplete! '
                    \ .'See ":h g:vit_compiler".'
        echohl None
        return
    endif
    let compiler = cdict['compiler']
    let flags    = cdict['flags']
    let errregex = cdict['errregex']
    let numcomps = cdict['numcomps']

    " handle status of last compilation and early aborts
    if numcomps <= 0
        return
    endif
    " if no job has been created we can assume that it is dead (see :h job_status())
    let jobstat = exists('s:vcurrjob') ? job_status(s:currjob) : 'dead'
    if g:vit_is_compiling && jobstat == 'run'
        let g:vit_compilation_queued = 1
        echomsg 'Compilation for buffer "'.a:buf.'" queued.'
        return
    else
        let g:vit_is_compiling = 0
        " if this is the first call to this function, we also want to reset the
        " 'compilation_queued' variable, since that is the current call
        if a:currentcomp is v:none
            let g:vit_compilation_queued = 0
        endif
    endif

    " handle error signs, quickfix list, etc. resets
    " do this for sure if the signs var is not empty, so we don't accidentally keep
    " around signs that the user wanted to disable
    if g:vit_max_errors > 0 || !empty(g:vit_signs)
        let g:vit_signs = {}
        call sign_unplace('ViT')
        call setqflist([], 'r')
    endif

    " now we are actually gonna compile! yay
    redraw | echo 'Compiling No. '.currentcomp.' of '.numcomps.'...'
    let cmd = s:PrepareArgs([compiler, flags], fnameescape(filepath))
    if a:silent == '!' || a:silent == '1' || a:silent == 1 || a:silent is v:true
        let s:currjob = job_start(cmd, #{cwd: pwd,
                    \ callback: {_, msg -> vit#CompileCallback(msg, a:buf, errregex)},
                    \ exit_cb: {_, exit -> vit#CompileExitCallback(exit, numcomps, a:buf,
                        \ a:silent, a:compiler, pwd, currentcomp)},
                    \ })
    else
        let term_buffer = term_start(cmd, #{cwd: pwd,
                    \ callback: {_, msg -> vit#CompileCallback(msg, a:buf, errregex)},
                    \ exit_cb: {_, exit -> vit#CompileExitCallback(exit, numcomps, a:buf,
                        \ a:silent, a:compiler, pwd, currentcomp)},
                    \ })
        let s:currjob = term_getjob(term_buffer)
    end

    let g:vit_is_compiling = 1
endfunction

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ COMPILATION CALLBACK ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

function vit#CompileCallback(msg, buf, errregex)
    " check if error parsings are even enabled in this pass
    if g:vit_max_errors < 1 || g:vit_num_errors >= g:vit_max_errors
        return
    endif

    " do actual list match so we can extract the right parts
    let match = matchlist(a:msg, a:errregex)
    if empty(match)
        return
    endif
    let [_, file, line, error; _] = match
    " assume current file if none given, if buffer is not found, abort
    let errbuf = bufnr(empty(file) ? a:buf : file)
    if errbuf == -1
        return
    endif
    " if no line or error is given, abort
    if empty(line) || empty(error)
        return
    endif

    " place sign (0 for allocating new identifier)
    call sign_place(0, 'ViT', 'ViTError', errbuf, #{lnum: line})
    " place in quickfix list
    call setqflist([
                \ #{bufnr: errbuf, lnum: line, text: error,
                \   type: 'E', module: bufname(errbuf), valid: 1}],
                \ 'a')
    " set signs for hover function, format is 'bufnr:line' for keys
    let g:vit_signs[errbuf.':'.line] = error

    " TODO: look into printing status messages for this callback
endfunction

function vit#CompileExitCallback(exit, numcomps, buf, silent, compiler, pwd, currentcomp)
    let g:vit_is_compiling = 0

    if a:currentcomp < a:numcomps
        " call the function again and return
        call vit#Compile(a:buf, a:silent, a:compiler, a:pwd, a:currentcomp + 1)
        return
    endif
    if g:vit_compilation_queued
        " if a compilation was queued, just call that again now and return
        let g:vit_compilation_queued = 0
        call vit#Compile(a:buf, a:silent, a:compiler, a:pwd, v:none)
        return
    endif

    " handle success message
    if a:exit == 0
        echohl MoreMsg  | redraw | echo 'Compiled succesfully! Yay!' | echohl None
    else
        echohl ErrorMsg | redraw | echo 'Compiled with errors... :(' | echohl None
    endif
endfunction

function vit#CompileSignHover()
    " key format as described in ViT#CompileCallback
    let err = get(g:vit_signs, bufnr().':'.line('.'), v:none)
    if !(err is v:none || empty(err))
        echohl ErrorMsg | redraw | echo err | echohl None
    endif
endfunction

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ TEMPLATING FUNCTIONS ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

" Sets up a new ViT template.
" Arguments:
"   name, the name of the command to be defined
"   keybind, the keybind to access this command, or '' for no keybind
"   inlinemode, '0' for no inline mode, '1' for inline mode
"   finalcursoroffset, the position that the cursor will be set to
"       upon completing the template
"   middleindent, the indent of text that the template surrounds in
"       surround mode
"   textbefore, an array of lines for the before-text
"   textafter, an array of lines for the after-text
"   [numargs,] the number of template parameters '#1, #2, ...' in the
"       'text(before|after)' arguments
"   [...,] the rest parameter contains the names of the template
"        parameters, see 'ViTPromptTemplateCompletion'
function vit#NewTemplate(name, keybind, inlinemode,
            \ finalcursoroffset, middleindent, textbefore, textafter,
            \ numargs = 0, argname = [], argdefault = [], argcomplete = [])
    let id = rand(srand())
    " ~~~~~~~~~~ command function
    function! ViTNewCommandSub_{id}_{a:name}(mode = 'i', col = 0) range closure
        let [textbefore, textafter] = [a:textbefore, a:textafter]
        let [lstart, lend] = [a:firstline, a:lastline]
        " possibly flip start and end
        if lstart > lend | let [lstart, lend] = [lend, lstart] | endif
        " setting cursor and line based on mode
        if a:mode == '' || (a:mode == 'i' && a:inlinemode == 1)
            " inline insert mode
            let [cstart, cend] = [a:col, a:col]
        elseif a:mode == 'i' || a:mode == 'V'
            " line insert mode
            let [textbefore, textafter] = [textbefore + [''], [''] + textafter]
            let [cstart, cend] = [0, 999999]
        elseif a:mode == 'v'
            " character insert mode
            let [cstart, cend] = [col("'<"), col("'>") + 1]
            " possibly flip start and end
            if cstart > cend | let [cstart, cend] = [cend, cstart] | endif
        else
            throw 'Unknown mode "'.a:mode.'".'
        endif
        " save undo state
        let undostate = undotree()['seq_cur']
        " insert
        call vimse#SmartSurround(
                            \ lstart, lend, cstart, cend,
                            \ textbefore, textafter, a:middleindent)
        " handle templating
        let result = vimse#TemplateString(lstart,
                    \ lend + len(textbefore) + len(textafter),
                    \ 0, 999999, a:numargs, a:argname, a:argdefault, a:argcomplete)
        " undo and return if result was false
        if !result && g:vit_template_remove_on_abort
            " set to 'undostate' for all other changes
            " and undo once for this method
            silent execute 'undo '.undostate | silent undo | return
        endif
        " else set cursor pos in new text
        call cursor(lstart + get(a:finalcursoroffset, 0, 0),
                    \ a:col + get(a:finalcursoroffset, 1, 0))
    endfunction

    let funcname = 'ViTNewCommandSub_'.id.'_'.a:name
    " ~~~~~~~~~~ keymaps
    if !empty(trim(a:keybind)) && g:vit_enable_keybinds
        execute 'inoremap <buffer> '.a:keybind.' <C-O>:call '
                    \ .funcname.'("i", col("."))<CR>'
        execute 'xnoremap <buffer> '.a:keybind.' :call '
                    \ .funcname.'(visualmode(), col("."))<CR>'
    endif
    " ~~~~~~~~~~ commands
    if g:vit_enable_commands
        execute 'command! -buffer -range -nargs=0 '.a:name
                    \ .' :<line1>,<line2>call '.funcname.'("i", col("."))'
    endif
    " return function reference for convenience, you're welcome ;>
    return funcref(funcname)
endfunction

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ FILE TREE ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

function vit#ResetRootFile(buf)
    let buf = bufname(a:buf)
    call s:ResetVar(buf, 'vit_file_tree', s:MakeFileNode(buf))
endfunction

function vit#AddParentFile(buf, filename)
    call vitnode#AddParentNode(s:GetRootNode(a:buf), s:MakeFileNode(a:filename))
endfunction

function vit#GetRootFile(buf)
    return get(s:GetRootNode(a:buf), 'data', v:none)
endfunction

function s:GetRootNode(buf)
    let node = s:GetVar(bufname(a:buf), 'vit_file_tree')
    " skip this loop if node is none
    while !(node is v:none) && (len(node['parents']) > 0)
        if len(node['parents']) > 1
            echohl ErrorMsg
            echomsg 'A ViT file tree node cannot have multiple parents. '
                        \ .'Offending node is '.vitnode#ToString(node, 1)
            echohl None
        endif
        let node = node['parents'][0]
    endwhile
    if node is v:none
        echohl ErrorMsg
        echomsg 'This buffer has no root file set. Something went wrong with ViT...'
        echohl None
    endif
    return node
endfunction

function s:MakeFileNode(filename)
    return vitnode#Node(s:PrepareFname(a:filename, 1))
endfunction

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ MODELINE ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

" Sets the vit_compiler, vit_num_compilations variable, and what larger file tree this
" file is included in based on the following syntax:
"
"     Modeline      ::= ^ .* '%' \s* 'ViT' \s+ ( <Compilation> | <WriteCompile>
"                           | <Included> ) \s* $ ;
"
"     Included      ::= 'included in' \s+ <File> ;
"     File          ::= .+ ;
"
"     Compilation   ::= <Numcomps> ( \s+ <OnWrite> )?
"                           ( \s+ <Compiler> ( \s+ <CompilerFlags> )? )? ;
"     OnWrite       ::= 'onwrite' | 'on-write' | 'onsave' | 'on-save' ;
"     Numcomps      ::= ( 'x' \d\+ ) | ( \d\+ 'x' ) ;
"     Compiler      ::= '-' | \w+ ;
"     CompilerFlags ::= '-' | .+ ;
"
" For instance ' Something Here % ViT  x2 pdflatex -file-line-error' would be interpreted
" as having the compilers ['pdflatex', 'pdflatex'] with the arguments ['-file-line-error,
" '-file-line-error'] and 2 compilations. The text ' Something Here ' is fully ignored.
" When <Compiler> or <CompilerFlags> are set to '-', the global value is assumed,
" otherwise the empty string.
"
" Multiple modelines can be put in the first lines of the document, so one might set both
" the compilation flags and the included-in flag by doing the following:
"
"   % ViT included in ../main.tex
"   % ViT x2 onwrite xetex -etex
"
" A file tree is traversed bottom-up, so the compilation runs once on the top of the tree
" but the settings from the lower files override the 'higher' settings.
"
" A common use case is '% ViT x2', where we instruct ViT to compile twice, but keep the
" same compiler as configured in g:vit_compiler.
"
" Arguments:
"   buf, the buffer to set options in (most likely current buffer) and start parsing at
"   [numlines,] how many lines to parse before giving up, defaults to 15
"   [maxdepth,] the number of files the buffer is included in to traverse before giving
"       up, defaults to 8
function vit#ParseModeline(buf, numlines = 15, maxdepth = 15)
    let buf = bufname(a:buf)
    " reset variables so we don't keep adding onto them when we reload the modelines
    call vit#ResetRootFile(buf)
    call s:ResetVar(buf, 'vit_compiler')
    call s:ResetVar(buf, 'vit_compile_on_write')
    " call the work-horse
    call s:ParseModeline(a:buf, buf, 0, a:numlines, a:maxdepth)
endfunction

" Recursive work-horse of vit#ParseModeline().
" Arguments:
"   buf, the buf to set options in (most likely current buffer)
"   file, the file to read lines from
"   depth, the current recursive depth
"   numlines, the number of lines to read from 'file'
"   maxdepth, the number of recursive calls to perform before giving up
function s:ParseModeline(buf, file, depth, numlines, maxdepth)
    " depth-test
    if a:depth >= a:maxdepth | return | endif
    " convenience variables
    let [modeline_pre, modeline_suf] = ['^.*%\s*ViT\s\+', '\s*$']
    " make sure we only read each header once
    let [read_compile, read_included_in] = [0, 0]
    " read in text-mode so ''
    for line in readfile(a:file, '', a:numlines)
        " ~~~~~~~~~~~~~~~~~~~~ up until here pre-order traversal ~~~~~~~~~~~~~~~~~~~~
        " ~~~~~~~~~~ included-in modeline
        let match = matchlist(line,
                    \ modeline_pre
                    \ .'included in\s\+\(.\+\)'
                    \ .modeline_suf)
        if !empty(match)
            if read_included_in != 0
                echohl ErrorMsg
                echomsg 'Found duplicated included-in ViT modeline in line ('.a:file.'):'
                echomsg '  '.line
                echohl None
                break
            else
                let read_included_in += 1
            endif
            let includedin = match[1]
            " file
            if !empty(includedin)
                " get actual path of the file
                let file = s:PrepareFname(includedin, 1)
                " modify file tree
                call vit#AddParentFile(a:buf, file)
                " parse modeline of includedin file
                call s:ParseModeline(a:buf, file, a:depth + 1, a:numlines, a:maxdepth)
            endif
            " skip to next line
            continue
        endif
        " ~~~~~~~~~~~~~~~~~~~~ now post-order traversal ~~~~~~~~~~~~~~~~~~~~
        " ~~~~~~~~~~ compilation modeline
        let match = matchlist(line,
                    \ modeline_pre
                    \ .'\%(x\=\(\d\+\)x\=\)'
                    \ .'\%(\s\+\(onwrite\|on-write\|onsave\|on-save\)\)\='
                    \ .'\%(\s\+\(\%(\w\+\)\|\-\)'
                        \ .'\%(\s\+\(\%(.\+\)\|-\)\)\=\)\='
                    \ .modeline_suf)
        if !empty(match)
            if read_compile != 0
                echohl ErrorMsg
                echomsg 'Found duplicated compiler ViT modeline in line ('.a:file.'):'
                echomsg '  '.line
                echohl None
                break
            else
                let read_compile += 1
            endif
            let [numcomps, onwrite, comp, compflags]
                    \ = [match[1], match[2], match[3], match[4]]
            " handle logic where we set both comp and compflags to '-' if they are empty
            " in case the user wants to just write '% ViT x3' without resetting the
            " compiler and its flags
            if empty(comp) && empty(compflags)
                let [comp, compflags] = ['-', '-']
            endif
            let vit_compiler = s:GetVar(a:buf, 'vit_compiler')
            " num compilations
            if !empty(numcomps)
                let vit_compiler['numcomps'] = str2nr(numcomps)
            endif
            " on-write
            if !empty(onwrite)
                call setbufvar(a:buf, 'vit_compile_on_write', 1)
            endif
            " compiler
            if comp != '-'
                let vit_compiler['compiler'] = comp
            endif
            " compiler flags
            if compflags != '-'
                let vit_compiler['flags'] = compflags
            endif
            " skip to next line
            continue
        endif
    endfor
endfunction

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ TeX UTILITY FUNCTIONS ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

" Moves cursor to the right to simulate the <Tab> behavior in other IDEs.
" Arguments:
"   [chars,] defaults to 'g:vit_jump_chars', a list of characters to
"       consider for a new column
function vit#SmartMoveCursorRight(chars = g:vit_jump_chars)
    let [lnum, col, line] = [line('.'), col('.'), getline('.')]
    " do actual smart movey things
    let cols = []
    for char in a:chars
        let newidx = stridx(line, char, col - 1) + 2
        " only add after cursor
        if newidx > col
            let cols += [newidx]
        endif
        " break loop if we found a min already
        if newidx == col + 1
            break
        endif
    endfor
    call cursor(lnum, len(cols) > 0 ? min(cols) : 999999)
endfunction

" Returns the name of the LaTeX environment the cursor is currently positioned in.
function vit#CurrentTeXEnv()
    let flags = 'bcnWz'
    " search for \begin{...} \end{...}
    let [lnum, col] = searchpairpos('\\begin{\_[^@\}#]\+}', '',
                                  \   '\\end{\_[^@\}#]\+}', flags)
    " now we get '\begin{envname}'
    let envname = get(matchlist(getline(lnum), '\\begin{\(\_[^@\}#]\+\)}', col - 1), 1, '')
    return envname
endfunction

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ MISC UTILITY FUNCTIONS ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

" Resets variable 'name' to copy of the global value 'g:name' in buffer 'buf' or to
" 'default' if global variable is not found.
function s:ResetVar(buf, name, default = v:none)
    call setbufvar(bufname(a:buf), a:name,
                \ exists('g:'.a:name) ? copy(g:{a:name}) : a:default)
endfunction

" Retrieves the variable 'name' in buffer 'buf', or sets the value to 'default' if it is
" not found and no global value 'g:name' exists, otherwise set to copy of 'g:name'.
function s:GetVar(buf, name, default = v:none)
    let buf = bufname(a:buf)
    " reset if not found already
    let bufvar = getbufvar(buf, a:name)
    if bufvar is v:none
        call s:ResetVar(buf, a:name, a:default)
        return getbufvar(buf, a:name)
    else
        return bufvar
    endif
endfunction

" Prepare a list of argument strings for a process.
function s:PrepareArgs(args, filepath)
    " replace % with the file in flags, \\\@<!% means match '%' only if it is not
    " preceeded by '\', so that we can escape % with \%
    return substitute(join(a:args, ' '), '\\\@<!%', a:filepath, 'g')
endfunction

" Same functionality as s:PrepareFname() but applied to a whole list of names.
function s:PrepareFnames(fnames, showerror = v:true, pwd = v:null)
    let out = []
    for fname in a:fnames
        let newfname = s:PrepareFname(fname, a:showerror, a:pwd)
        if !empty(newfname) | let out += [newfname] | endif
    endfor
    return out
endfunction

" Make sure file name points to an actually existing file and make the path relative to
" the given pwd or the cwd if no value is given.
" Arguments:
"   fname, a filename to modify
"   [showerror,] if true, display an error message for an invalid file pointer, otherwise
"       just siltently ignore the file
"   [path,] the path to search in if the file is not found immediately, defaults to the
"       current working directory
function s:PrepareFname(fname, showerror = v:true, path = v:null)
    let path = (a:path is v:null) ? getcwd() : a:path
    if filereadable(a:fname)
        " nothing needs to be done
        return a:fname
    endif
    " try to find file
    let tmpwd = fnamemodify(a:fname, ':h')
    let tmpfname = fnamemodify(a:fname, ':t')
    let found = findfile(tmpfname, tmpwd)
    if empty(found) || !filereadable(found)
        if !a:showerror | return | endif
        echohl ErrorMsg
        redraw | echomsg 'Unable to locate file "'.tmpfname.'" relative to "'.tmpwd.'"'
        echohl None
    else
        return fnamemodify(found, ':p')
    endif
endfunction

" Opens a read-only status buffer in another window.
function vit#Status(buf)
    let buf = bufname(a:buf)
    " check if we should even be able to open it here
    if &filetype != 'latex'
        echo 'Not a ViT buffer.' | return
    endif

    let title = 'ViT Status for "'.buf.'"'
    " wipe previous buffer, if there is one
    if bufexists(title)
        execute 'bwipeout! '.bufnr(title)
    endif
    " make new buffer
    let statbuf = bufadd(title)
    " load buffer
    call bufload(statbuf)
    if !bufexists(statbuf) || !bufloaded(statbuf)
        echo 'Unable to create and load status buffer for ViT.' | return
    endif

    " set string list, this is all in Markdown format
    let strs = ['# '.title, '']

    call add(strs, '## Compiler:')
    call add(strs, '```')
    call add(strs, '  {')
    for [key, value] in items(s:GetVar(buf, 'vit_compiler'))
        call add(strs, '    '.string(key).': '.string(value).',')
    endfor
    call add(strs, '  }')
    call add(strs, '```')
    call add(strs, '')
    call add(strs, 'Compiles on write: '
                \ .(s:GetVar(buf, 'vit_compile_on_write') ? 'Yes' : 'Nope'))
    call add(strs, '')

    call add(strs, '## File Tree:')
    call add(strs, '```')
    call extend(strs, vitnode#ToString(s:GetRootNode(buf), 1))
    call add(strs, '```')
    call add(strs, '')
    " write string list

    call appendbufline(statbuf, 0, strs)

    " open the buffer, bufnr just to make sure we don't use a name with spaces here
    execute 'sbuffer +setlocal\ buftype=nofile\ readonly\ '
                \ .'filetype=markdown\ nospell '.bufnr(statbuf)
endfunction

" Returns a very approximate byte size for a variable.
function vit#SizeOf(EL)
    let [t, size] = [type(a:EL), 0]
    if t is v:t_list
        for E in a:EL | let size += vit#SizeOf(E) | endfor
    elseif t is v:t_dict
        for [K, V] in items(a:EL) | let size += vit#SizeOf(K) + vit#SizeOf(V) | endfor
    elseif t is v:t_number || t is v:t_string || t is v:t_blob
        let size += len(a:EL)
    else
        let size += 1
    endif
    return size
endfunction

