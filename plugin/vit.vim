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
call s:Config('g:vit_enable_completion', {-> 1})
call s:Config('g:vit_enable_scanning', {-> 1})
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
call s:Config('g:vit_static_commands', {->
            \ #{latex: readfile(findfile('latex_commands.txt', &runtimepath))}}, {})
call s:Config('g:vit_includes', {-> ['latex']})
call s:Config('g:vit_autosurround_chars', {->
            \ [['(', ')'], ['[', ']'], ['{', '}'], ['$', '$']]})

" TODO: maybe document this
call s:Config('g:vit_commands', {-> copy(g:vit_static_commands)}, {})
" TODO: maybe document this
call s:Config('g:vit_included_in', {-> []})
" TODO: maybe document this
call s:Config('g:vit_scan_prg', {->
            \ exepath(findfile('bin/scan_latex_sources', &runtimepath))})

" TODO: maybe document this
call s:Config('g:vit_signs', {-> {}})
call s:Config('g:vit_num_errors', {-> 0})
call s:Config('g:vit_is_compiling', {-> 0})
call s:Config('g:vit_compilation_queued', {-> 0})

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ SIGNS ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

highlight ViTErrorSign ctermfg=Red ctermbg=DarkRed
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
    " set up variables
    let pwd = (a:pwd is v:none) ? getcwd() : a:pwd
    let currentcomp = (a:currentcomp is v:none) ? 1 : a:currentcomp
    let filepath = vit#RootFile(a:buf)
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
    let g:vit_signs[errbuf..line] = error

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

    " scan if enabled
    if g:vit_enable_scanning
        call vit#FullScan(a:buf, a:pwd)
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
    let err = get(g:vit_signs, bufnr()..line('.'), v:none)
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
"   class, determines which local class this command template is a part of, acts globally
"       if the set class is 'latex'
"   keybind, the keybind to access this command, or '' for no keybind
"   inlinemode, '0' for no inline mode, '1' for inline mode
"   completionitem, whether to make this tempalte an auto-completion
"       entry upon creating the command (and possibly keybinds),
"       the call to 'vit#NewCompletionOption' will be made using
"       the first item of 'textbefore'
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
function vit#NewTemplate(name, class, keybind, inlinemode, completionitem,
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
                    \ .funcname.'(visualmode(), col("."))'
    endif
    " ~~~~~~~~~~ completion
    if a:completionitem && len(a:textbefore) > 0
        call vit#NewCompletionOption(
                    \ a:textbefore[0],
                    \ a:class,
                    \ 'call '.funcname.'("i", col("."))')
    endif
    return funcref(funcname)
endfunction

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ COMPLETION ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

" Adds completion option 'name' to 'class' globally.
" Arguments:
"     - name, the name of the completion option item
"     - class, the class this completion option item belongs to
"     - [command,] the command to execute when using this completion option item,
"           defaults to '' which means the contents of 'name' will be inserted in
"           place of executing a command
"     - [static,] determindes whether to add to the static commands or not
function vit#NewCompletionOption(name, class, command = '', static = 0)
    " create new completion option item
    let item = empty(a:command)
                \ ? a:name
                \ : #{word: a:name, user_data: 'vit_'.a:command}
    " check if key exists in commands
    let normed = s:NormClass(a:class)
    let vit_commands = a:static ? g:vit_static_commands : g:vit_commands
    if has_key(vit_commands, normed)
        let l = vit_commands[normed]
        " check if something similar exists and remove that so we do not
        " end up with '\abc' and '\abc{' simultaneously
        " and also remove a '{' '\abc{' to check for '\abc'
        for suffix in ['', '[', '{']
            " add suffix
            let idx = index(l, a:name.suffix, 0, 0)
            if idx != -1 | call remove(l, idx) | endif
            " (try to) remove suffix
            if a:name[-1] == suffix
                let idx = index(l, a:name[:-2])
                if idx != -1 | call remove(l, idx) | endif
            endif
        endfor
        let l += [item]
    else
        let vit_commands[normed] = [item]
    endif
endfunction

" see :h complete-functions for more details
function vit#CompleteFunc(findstart, base)
    " get last 'word' under cursor
    if a:findstart
        let searchspace = strpart(getline('.'), 0, col('.') - 1)
        return max([0,
                  \ strridx(searchspace, ' ') + 1,
                  \ strridx(searchspace, '\')])
    endif
    let matches = [a:base]
    let matches += matchfuzzy(
                \ vit#GetCompletionOptions(bufname()),
                \ a:base, #{key: 'word'})
    return matches
endfunction

" Deletes the just inserted item and replaces it with a command encoded
" in the 'user_data' of the completion menu item if it came from this
" plugin.
function vit#CompletionDetection()
    let item = v:completed_item
    " stop if user_data does not exist on the item
    if empty(item) || !has_key(item, 'user_data')
        return
    endif
    " split into [WHOLE_MATCH, Command, mode, ...] or []
    let match = matchlist(item['user_data'], 'vit_\(.*\)')
    " return if we did not find at least [WHOLE_MATCH, Command]
    if empty(get(match, 0, '')) || empty(get(match, 1, ''))
        return
    endif
    " construct new line with removed 'word'
    let [lnum, col, line] = [line('.'), col('.'), getline('.')]
    let wordlen = strlen(item['word'])
    let newline = strpart(line, 0, col - wordlen - 1).strpart(line, col - 1, 999999)
    call setline(lnum, newline)
    " put cursor back
    call setpos('.', [bufnr(), lnum, col - wordlen])
    " execute command given by item
    execute match[1]
endfunction

" Removes the completion option items from a global class.
function vit#ResetCompletionOptionClass(class)
    let normed = s:NormClass(a:class)
    let g:vit_commands[normed] = copy(get(g:vit_static_commands, normed, []))
endfunction

" Returns the completion options stored internally for 'name'.
function vit#GetCompletionOption(name)
    " we try it without and with normalization
    let out = get(g:vit_commands, a:name, [])
    if !empty(out) | return out | endif
    let out = get(g:vit_commands, s:NormClass(a:name), [])
    return out
endfunction

" Returns all the currently visible completion options. This is using the 'vit_includes'
" and 'vit_included_in' buffer variables to filter out what is in scope.
function vit#GetCompletionOptions(buf)
    if !g:vit_enable_completion | return [] | endif
    let vit_includes = s:GetVar(a:buf, 'vit_includes')
    " vit_includes is normed but vit_included_in has the acutal path to the file,
    " so we have to be careful
    let vit_included_in = s:GetVar(a:buf, 'vit_included_in')
    " we have to return a flat array of only keys found in classlist, so we loop and make
    " that list here
    let [out, classlist] = [[], vit_includes + vit_included_in]
    for name in classlist | let out += vit#GetCompletionOption(name) | endfor
    return out
endfunction

" Marks 'class' as included in buffer 'buf'.
function vit#Include(buf, class)
    let vit_includes = s:GetVar(a:buf, 'vit_includes')
    let normed = s:NormClass(a:class)
    if index(vit_includes, normed) == -1
        let vit_includes += [normed]
    endif
endfunction

" Resets the included classes in buffer 'buf' to the default global value.
function vit#ResetInclude(buf)
    call s:ResetVar(a:buf, 'vit_includes')
    " files need to include themselves anyway
    call vit#Include(a:buf, bufname(a:buf))
endfunction

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ SCANNING ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

" Scans all the files and logs that can be found, including those in the included-in tree.
function vit#FullScan(buf, pwd = v:null)
    let buf = bufname(a:buf)
    let pwd = (a:pwd is v:null) ? getcwd() : a:pwd
    " we wanna load all files we are included in since we can access
    " those commands as well
    let _names = [buf] + s:GetVar(buf, 'vit_included_in')
    " prepare the fnames, to make sure we filter out non-existent ones and so on
    let texnames = s:PrepareFnames(_names, 1, pwd)
    let lognames = s:PrepareFnames(
                \ mapnew(_names, {_, v -> fnamemodify(v, ':r').'.log'}), 0, pwd)
    " just check if root log is there, otherwise something is very fishy
    call s:PrepareFname(fnamemodify(vit#RootFile(buf), ':r').'.log', 1, pwd)
    " if there is no root log, something is off
    " clear which files are marked as included, since those will be reread now in case
    " something along the tree changed
    call vit#ResetInclude(buf)
    " now we run the scan, with 'noremove' set to false since we wanna clear everything
    " and re-introduce it, as above
    call vit#ScanFromFnames(buf, texnames + lognames, 0, pwd)
endfunction

" Scans the current buffer for changes in definitions.
function vit#ScanFromBuffer(buf, noremove = 1, pwd = v:null)
    let pwd = (a:pwd is v:null) ? getcwd() : a:pwd
    " call job
    let g:vit_scan_currjob = job_start(g:vit_scan_prg,
                \ {'out_cb': {_, msg ->
                        \ vit#ScanFileCallback(a:buf, msg, a:noremove, bufname(a:buf))},
                \  'in_io': 'buffer', 'in_buf': bufnr(a:buf),
                \  'cwd': pwd})
endfunction

" Scans all the given file names for changes in definitions.
function vit#ScanFromFnames(buf, fnames, noremove = 1, pwd = v:null)
    let pwd = (a:pwd is v:null) ? getcwd() : a:pwd
    " escape the file names just to make sure
    let fnames = mapnew(a:fnames, {_, v -> fnameescape(v)})
    " call job
    let g:vit_scan_currjob = job_start([g:vit_scan_prg] + fnames,
                \ {'out_cb': {_, msg ->
                        \ vit#ScanFileCallback(a:buf, msg, a:noremove)},
                \  'cwd': pwd})
endfunction

" Callback for executions of the 'util/scan_latex_sources' utility.
" Arguments:
"   buf, the buffer to change variables of
"   msg, set by the job callback
"   noremove, whether or not to remove the commands in an include, helpful for when you
"       parse log files and reintroduce those commands anyway
"   [stdinname,] the class name to use when reading from stdin, defaults to '' when not
"       needed and ignored
function vit#ScanFileCallback(buf, msg, noremove, stdinname = '', cleared_cls = []) abort
    let [type, class; rest] = split(a:msg, ' ')
    if class == '<stdin>' | let class = a:stdinname | endif
    if type == 'include'
        " we don't wanna reset completion options classes if we are reading
        " from a single buffer and/or noremove is set
        if !a:noremove && index(a:cleared_cls, class) == -1
            call vit#ResetCompletionOptionClass(class)
            call add(a:cleared_cls, class)
        endif
        " mark this file as included
        call vit#Include(a:buf, class)
    elseif type == 'command'
        let [cmdname, numargs; _] = rest
        call vit#NewCompletionOption((numargs > 0) ? cmdname.'{' : cmdname, class)
    elseif type == 'environ'
        let [cmdname; _] = rest
        call vit#NewTemplate(substitute('ViT'.cmdname, '\*\|#\|-', '_ill', 'g'), class,
                    \ '', 0, 1, [1, 5], 4,
                    \ ['\begin{'.cmdname.'}'], ['\end{'.cmdname.'}'])
    else
        echohl ErrorMsg
        redraw
        echomsg 'Unknown ScanFiles tuple type "'.type.'"'
        echohl None
    endif
endfunction

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ MODELINE ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

" Sets the vit_compiler, vit_num_compilations variable, and what larger file tree this
" file is included in based on the following syntax:
"
"     Modeline      ::= ^ .* '%' \s* 'ViT' \s+ ( <Compilation> | <Included> ) \s* $ ;
"
"     Included      ::= 'included in' \s+ <File> ;
"     File          ::= .+ ;
"
"     Compilation   ::= <Numcomps> ( \s+ <Compiler> ( \s+ <CompilerFlags> )? )? ;
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
"   % ViT x2 xetex -etex
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
function vit#ParseModeline(buf, numlines = 15, maxdepth = 8)
    let buf = bufname(a:buf)
    " reset variables so we don't keep adding onto them when we reload the modelines
    call s:ResetVar(buf, 'vit_included_in')
    call s:ResetVar(buf, 'vit_compiler')
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
                " set included in
                let vit_included_in = s:GetVar(a:buf, 'vit_included_in')
                let vit_included_in += [file]
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
                    \ .'\%(\s\+\(-\|\%(\w\+\)\)\%(\s\+\(-\|\%(.\+\)\)\)\=\)\='
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
            let [numcomps, comp, compflags] = [match[1], match[2], match[3]]
            " handle logic where we set both comp and compflags to '-' if they are empty
            " in case the user wants to just write '% ViT x3' withotu resetting the
            " compiler and its flags
            if empty(comp) && empty(compflags)
                let [comp, compflags] = ['-', '-']
            endif
            let vit_compiler = s:GetVar(a:buf, 'vit_compiler')
            " num compilations
            if !empty(numcomps)
                let vit_compiler['numcomps'] = str2nr(numcomps)
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

" Returns the root file of the include-tree of 'buf'.
function vit#RootFile(buf)
    let vit_included_in = s:GetVar(a:buf, 'vit_included_in')
    return empty(vit_included_in) ? bufname(a:buf) : vit_included_in[-1]
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

" Resets variable 'name' to the global value 'g:name' in buffer 'buf'.
function s:ResetVar(buf, name)
    call setbufvar(bufname(a:buf), a:name, copy(g:{a:name}))
endfunction

" Retrieves the variable 'name' in buffer 'buf', or from the global variable 'g:name' if
" 'global' is set to a truthy value.
function s:GetVar(buf, name, global = 0)
    let buf = bufname(a:buf)
    " reset if not found already
    if !exists('b:'.a:name) | call s:ResetVar(buf, a:name) | endif
    " return value
    return a:global ? g:{a:name} : getbufvar(buf, a:name)
endfunction

" Normalizes a path to a class string.
function s:NormClass(class)
    return fnamemodify(a:class, ':t:r')
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

    " set string list
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

    call add(strs, '## Inclusion Branch:')
    call add(strs, '```')
    for file in getbufvar(buf, 'vit_included_in')
        call add(strs, '  '.file
                    \ .' (defines '.len(vit#GetCompletionOption(file)).' command[s])')
        call add(strs, '        ^')
        call add(strs, '        |')
    endfor
    call add(strs, '  '.buf
                \ .' (defines '.len(vit#GetCompletionOption(buf)).' command[s])')
    call add(strs, '```')

    call add(strs, '')

    call add(strs, '## Includes:')
    for cls in getbufvar(buf, 'vit_includes')
        call add(strs, '  - '.cls
                    \ .' (defines '.len(vit#GetCompletionOption(cls)).' command[s])')
    endfor

    " write string list
    call appendbufline(statbuf, 0, strs)

    " open the buffer, bufnr just to make sure we don't use a name with spaces here
    execute 'sbuffer +setlocal\ buftype=nofile\ readonly\ '
                \ .'filetype=markdown\ nospell '.bufnr(statbuf)
endfunction

