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

" TODO: document vit_enable_* options and compiler options
" -
call s:Config('g:vit_enable', {-> 1})
if !g:vit_enable | finish | endif

call s:Config('g:vit_enable_keybinds', {-> 1})
call s:Config('g:vit_leader', {-> '<C-@>'})
call s:Config('g:vit_jump_chars', {-> [' ', '(', '[', '{']})
call s:Config('g:vit_autosurround_chars', {->
            \ [['(', ')'], ['[', ']'], ['{', '}'], ['$', '$']]})

call s:Config('g:vit_num_compilations', {-> 1})
call s:Config('g:vit_compiler', {-> ['pdflatex', 'pdflatex']})
call s:Config('g:vit_compiler_flags', {->
            \ ['-interaction=nonstopmode -file-line-error', '-file-line-error']})

call s:Config('g:vit_max_errors', {-> 10})
call s:Config('g:vit_error_regexp', {->
            \ '^\s*\(.\{-1,}\)\s*:\s*\(\d\{-1,}\)\s*:\s*\(.\{-1,}\)\s*$'})

call s:Config('g:vit_enable_completion', {-> 1})
call s:Config('g:vit_static_commands', {->
            \ #{latex: readfile(findfile('latex_commands.txt', &runtimepath))}}, {})
call s:Config('g:vit_template_remove_on_abort', {-> 1})

call s:Config('g:vit_enable_scanning', {-> 1})
call s:Config('g:vit_commands', {-> copy(g:vit_static_commands)}, {})
call s:Config('g:vit_includes', {-> ['latex']})

" TODO: maybe document this
call s:Config('g:vit_scan_prg', {-> findfile('bin/scan_latex_sources', &runtimepath)})
call s:Config('g:vit_comment_line', {-> '% '.repeat('~', 70)})

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ COMPILING ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

" Compiles the contents of a file using the configured LaTeX compiler.
" Arguments:
"   filepath, the path to the file
"   pwd, the path to the working directory (should be folder of
"       'filepath' resides in)
"   [silent,] can be '!' to be executed as background job, otherwise
"       open a new terminal window
"   [flags,] can be set to pass flags to the compiler
"   [numcomp,] indicates how many times to compile the file, 0 indicates no
"       compilation at all
function vit#Compile(filepath, pwd, silent = '', flags = '',
            \        numcomp = v:none, currentcomp = v:none)
    " tell this buffer it is being compiled
    let buf = bufname(a:filepath)
    if exists('b:vit_is_compiling') && b:vit_is_compiling
        echohl ErrorMsg
        redraw
        echomsg 'Buffer "'.buf.'" is already being compiled.'
        echohl None
        return
    endif
    " set up vars
    let vit_compiler = s:GetVar(buf, 'vit_compiler')
    let vit_compiler_flags = s:GetVar(buf, 'vit_compiler_flags')
    let numcomp = (a:numcomp is v:none)
                \ ? s:GetVar(buf, 'vit_num_compilations')
                \ : a:numcomp
    if numcomp < 1
        return
    endif
    let currentcomp = (a:currentcomp is v:none) ? 1 : a:currentcomp
    " run compilation
    redraw | echo 'Compiling No. '.currentcomp.' of '.numcomp.'...'
    if a:silent == '!'
        " run background job
        if len(vit_compiler) < 1
            echohl ErrorMsg
            redraw
            echomsg 'No compiler defined for background process compilation in ViT: '
                \ .string(vit_compiler).' '.string(vit_compiler_flags)
            echohl None
            return
        endif
        let s:vit_compile_currjob = job_start(
            \ join([vit_compiler[0], vit_compiler_flags[0],
            \       a:flags, a:filepath], ' '),
            \ #{exit_cb: {_, exit ->
            \       vit#CompileCallback(exit, a:filepath, a:pwd, a:silent, a:flags,
            \                           numcomp, currentcomp)},
            \   cwd: a:pwd})
    elseif a:silent == ''
        " open terminal
        if len(vit_compiler) < 2
            echohl ErrorMsg
            redraw
            echomsg 'No compiler defined for terminal compilation in ViT: '
                \ .string(vit_compiler).' '.string(vit_compiler_flags)
            echohl None
            return
        endif
        :vertical :belowright call term_start(
            \ join([vit_compiler[1], vit_compiler_flags[1],
            \       a:flags, a:filepath], ' '),
            \ #{term_finish: 'close',
            \   exit_cb: {_, exit ->
            \       vit#CompileCallback(exit, a:filepath, a:pwd, a:silent, a:flags,
            \                           numcomp, currentcomp)},
            \   cwd: a:pwd})
    else
        echohl ErrorMsg
        redraw
        echomsg 'Unknown compilation option "'.a:silent.'" for "silent"'
        return
    endif
    let b:vit_is_compiling = 1
endfunction

if g:vit_max_errors > 0
    call sign_define('ViTError', #{text: '!>', texthl: 'ViTErrorSign'})
endif
" TODO: document the arguments of this function as it got quite complex
function vit#CompileCallback(exit, filepath, pwd, silent, flags, numcomp, currentcomp)
    " mark compilation as done
    let b:vit_is_compiling = 0
    " check if we still want to compile or not
    if a:currentcomp < a:numcomp
        " recursively call and go no farther in callback
        call vit#Compile(a:filepath, a:pwd, a:silent, a:flags,
                    \    a:numcomp, a:currentcomp + 1)
        return
    endif
    let buf = bufnr(a:filepath)
    " call scanning
    if g:vit_enable_scanning
        call vit#ScanFromLog(a:filepath, a:pwd)
    endif
    " remove old signs
    if g:vit_max_errors > 0
        call setbufvar(buf, 'vit_signs', {})
        call sign_unplace('ViT')
        call setqflist([], 'r')
    endif
    " handle success
    if a:exit == 0
        echohl MoreMsg | redraw | echo 'Compiled succesfully! Yay!' | echohl None
        return
    endif
    " handle errors
    try
        let statusmsgs = []
        " read signs dict
        let vit_signs_dict = getbufvar(buf, 'vit_signs', {})
        " loop over lines in logfile
        let logfile = readfile(findfile(fnamemodify(a:filepath, ':r').'.log', a:pwd))
        let [lnum, num_matched, logfile_len] = [0, 0, len(logfile)]
        while lnum < logfile_len && num_matched < g:vit_max_errors
            " try to match message for error
            let errmatch = matchlist(logfile[lnum], g:vit_error_regexp)
            if len(errmatch) < 3
                let lnum += 1
                continue
            endif
            let [errfile, errline, errmsg]
                        \ = [errmatch[1], str2nr(errmatch[2]), errmatch[3]]
            " place sign
            call sign_place(0, 'ViT', 'ViTError', buf, #{lnum: errline})
            " place quickfix list
            call setqflist([
                        \ #{bufnr: buf, lnum: errline, text: errmsg,
                        \   type: 'E', module: errfile, valid: 1}],
                        \ 'a')
            " set signs for hover func
            let vit_signs_dict[errline] = errmsg
            " add status message
            let statusmsgs += ['Compiled with errors (line '.errline.'): '.errmsg]
            " accounting
            let num_matched += 1
            let lnum += 1
        endwhile

        echohl ErrorMsg
        redraw
        if !empty(statusmsgs)
            echomsg statusmsgs[0]
        elseif g:vit_max_errors == 0
            echomsg 'Compiled wtih errors.'
        else
            echomsg 'Compiled with errors, but no error messages found in .log file.'
        endif
        echohl None
    catch /.*E484.*/
        echohl ErrorMsg
        redraw
        echomsg 'Compiled with errors, but found no .log file for this buffer.'
        echohl None
    endtry
endfunction

function vit#CompileSignHover()
    let vit_sign_msg = get(getbufvar(bufname(), 'vit_signs', {}), line('.'), '')
    if !empty(vit_sign_msg)
        echohl ErrorMsg | redraw | echo vit_sign_msg | echohl None
    endif
endfunction

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ HIGHLIGHTING GROUPS ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

highlight ViTErrorSign ctermfg=Red ctermbg=DarkRed

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
        for suffix in ['', '[', '{']
            let idx = index(l, a:name.suffix, 0, 0)
            if idx != -1 | call remove(l, idx) | endif
        endfor
        let l += [item]
    else
        let vit_commands[normed] = [item]
    endif
endfunction

" Removes the completion option items from a global class.
function vit#ResetCompletionOptionClass(class)
    let normed = s:NormClass(a:class)
    let g:vit_commands[normed] = copy(get(g:vit_static_commands, normed, []))
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
endfunction

function vit#GetCompletionOptions(buf)
    if !g:vit_enable_completion | return [] | endif
    let vit_includes = s:GetVar(a:buf, 'vit_includes')
    return flattennew(values(
                \ filter(g:vit_commands, 'index(vit_includes, v:key) != -1'),
            \ ))
endfunction

" Normalizes a path to a class string.
function s:NormClass(class)
    return split(a:class, '\.')[0]
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

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ SCANNING ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

" Scans the current buffer for changes in definitions. This operations will not delete
" any information and only consider additions.
function vit#ScanFromBuffer(buf, cwd)
    let g:vit_scan_currjob = job_start(g:vit_scan_prg,
                \ {'out_cb': {_, msg ->
                        \ vit#ScanFileCallback(a:buf, msg, 1, bufname(a:buf))},
                \  'in_io': 'buffer', 'in_buf': bufnr(a:buf),
                \  'cwd': a:cwd})
endfunction

" Scans the file with the given 'texname' by looking through the log, if such a log
" exists. This operation will re-scan all includes of buffer 'buf' and rebuild affected
" files in the global class cache.
function vit#ScanFromLog(buf, cwd)
    call vit#ResetInclude(a:buf)
    let g:vit_scan_currjob = job_start(g:vit_scan_prg.' '.bufname(a:buf),
                \ {'out_cb': {_, msg ->
                        \ vit#ScanFileCallback(a:buf, msg, 0)},
                \  'cwd': a:cwd})
endfunction

" Callback for executions of the 'util/scan.py' utility.
function vit#ScanFileCallback(buf, msg, noremove, stdinname = '') abort
    let [type, class; rest] = split(a:msg, ' ')
    if class == '<stdin>' | let class = a:stdinname | endif
    if type == 'include'
        " we don't wanna reset completion options classes if we are reading
        " from a single buffer and/or noremove is set
        if !a:noremove
            call vit#ResetCompletionOptionClass(class)
        endif
        " mark this file as included
        call vit#Include(a:buf, class)
    elseif type == 'command'
        let [cmdname, numargs; _] = rest
        call vit#NewCompletionOption((numargs > 0) ? cmdname.'{' : cmdname, class)
    elseif type == 'environ'
        let [cmdname; _] = rest
        call vit#NewTemplate(substitute('ViT'.cmdname, '\*\|#', '_ill', 'g'), class,
                    \ '', 0, 1, [1, 5], 4,
                    \ ['\begin{'.cmdname.'}'], ['\end{'.cmdname.'}'])
    else
        echohl ErrorMsg
        redraw
        echomsg 'Unknown ScanFiles tuple type "'.type.'"'
        echohl None
    endif
endfunction

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ UTILITY FUNCTIONS ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

" Resets variable 'name' to the global value 'g:name' in buffer 'buf'.
function s:ResetVar(buf, name)
    call setbufvar(a:buf, a:name, copy(g:{a:name}))
endfunction

" Retrieves the variable 'name' in buffer 'buf', or from the global variable 'g:name' if
" 'global' is set to a truthy value.
function s:GetVar(buf, name, global = 0)
    " reset if not found already
    if !exists('b:'.a:name) | call s:ResetVar(a:buf, a:name) | endif
    " return value
    return a:global ? g:{a:name} : getbufvar(a:buf, a:name)
endfunction

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

" Sets the vit_compiler, and vit_num_compilations variable based on the following syntax:
"
"     Modeline      ::= ^ .* '%' \s* 'ViT' \s+ <Numcomps>
"                           (\s+ <Compiler> (\s+ <CompilerFlags>)?)? \s* $
"     Numcomps      ::= x\d\+
"     Compiler      ::= '-' | \w+
"     CompilerFlags ::= .+
"
" For instance ' Something Here % ViT  x2 pdflatex -file-line-error' would be interpreted
" as having the compilers ['pdflatex', 'pdflatex'] with the arguments ['-file-line-error,
" '-file-line-error'] and 2 compilations. The text ' Something Here ' is fully ignored.
" When <Compiler> is set to '-', it assumes the global value. When no <Compiler> or
" <CompilerFlags> are found, they assume the global value.
"
" A common use case is '% ViT x2', where we instruct ViT to compile twice, but keep the
" same compiler as configured in g:vit_compiler.
function vit#ParseCompilationHeader(buf, numlines = 15)
    " reset old vars
    call s:ResetVar(a:buf, 'vit_num_compilations')
    call s:ResetVar(a:buf, 'vit_compiler')
    call s:ResetVar(a:buf, 'vit_compiler_flags')
    " parse
    let lines = getbufline(a:buf, 0, a:numlines)
    for line in lines
        let match = matchlist(line,
                    \ '^.*%\s*ViT\s\+'
                    \ .'x\(\d\+\)'
                    \ .'\%(\s\+\(-\|\%(\w\+\)\)\%(\s\+\(.\+\)\)\=\)\='
                    \ .'\s*$')
        if !empty(match)
            let [numcomps, comp, compflags] = [match[1], match[2], trim(match[3])]
            " num compilations
            if !empty(numcomps)
                let b:vit_num_compilations = str2nr(numcomps)
            endif
            " compiler
            let vit_compiler = s:GetVar(a:buf, 'vit_compiler')
            if !empty(comp) && comp != '-'
                for i in range(2)
                    let vit_compiler[i] = comp
                endfor
            endif
            " compiler flags
            let vit_compiler_flags = s:GetVar(a:buf, 'vit_compiler_flags')
            if !empty(compflags)
                for i in range(2)
                    let vit_compiler_flags[i] = compflags
                endfor
            endif
            " message
            redraw
            echo 'Found ViT modeline, compiling '
                \ .s:GetVar(a:buf, 'vit_num_compilations').' times '
                \ .'with '.string(vit_compiler).' as compiler with flags '
                \ .string(vit_compiler_flags)
            break
        endif
    endfor
endfunction

