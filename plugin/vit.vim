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
                    \ 'syntax/latex.vim', 'autoload/*.vim', 'user/*.vim']
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
            \ 'errregex': '^\s*\([[:fname:]]\{-}\)\s*:'
            \             .'\s*\(\d\+\)\s*:'
            \             .'\s*\([[:print:]]\{-}\)\s*$',
            \ 'numcomps': 1,
            \ 'statusline': 'sh -c "echo `detex % | wc -w` W"',
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
call s:Config('g:vit_compiler_ctx', {-> {
            \ 'is_compiling': 0,
            \ 'is_queued': 0,
            \ 'last_popupid': -1,
            \ }})
" This list is filled with dicts of the following form:
"   {
"     'name': str,
"     'keybind': str,
"     'firstline': str,
"     'preview': str,
"     'inlinemode': boolean,
"   }
call s:Config('g:vit_templates', {-> []})

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ SIGNS AND HIGHLIGHTS ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

highlight ViTErrorSign ctermfg=White ctermbg=DarkRed
call sign_define('ViTError', #{text: '!>', texthl: 'ViTErrorSign'})

highlight ViTCompileMsg ctermfg=Blue ctermbg=Black
highlight ViTSuccMsg ctermfg=Green ctermbg=Black
highlight ViTErrMsg ctermfg=DarkRed ctermbg=Black

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
function vit#Compile(buf, silent = '', compiler = {}, pwd = v:none, currentcomp = v:none)
    " set up variables
    let pwd = (a:pwd is v:none) ? getcwd() : a:pwd
    let currentcomp = (a:currentcomp is v:none) ? 1 : a:currentcomp
    let firstcall = a:currentcomp is v:none

    " parse modline again just in case it changed
    if firstcall | call vit#ParseModeline(a:buf) | endif
    " then get the root file
    let filepath = vit#GetRootFile(a:buf)

    " get from arguments first, then global value, finally resort to v:none
    let vit_compiler = vitutil#GetVar(a:buf, 'vit_compiler')
    function! GetCompiler(key) closure
        let result = get(a:compiler, a:key, get(vit_compiler, a:key, v:none))
        if result is v:none
            throw 'ViT: Unable to find value for compiler dictionary key "'
                        \ .a:key.'". See ":h g:vit_compiler" for help.'
        endif
        return result
    endfunction
    let compiler   = GetCompiler('compiler')
    let flags      = GetCompiler('flags')
    let errregex   = GetCompiler('errregex')
    let numcomps   = GetCompiler('numcomps')
    let statusline = GetCompiler('statusline')

    " update status line if this is the first call and we have a command set
    if firstcall && !(statusline is v:none) && len(statusline) > 0
        call s:UpdateStatusline(a:buf, statusline, filepath)
    endif

    " handle status of last compilation and early aborts
    if numcomps <= 0
        return
    endif
    " if no job has been created we can assume that it is dead (see :h job_status())
    let jobstat = exists('s:vcurrjob') ? job_status(s:currjob) : 'dead'
    if g:vit_compiler_ctx['is_compiling'] && jobstat == 'run'
        let g:vit_compiler_ctx['is_queued'] = 1
        echomsg 'ViT: Compilation for buffer "'.a:buf.'" queued.'
        return
    else
        let g:vit_compiler_ctx['is_compiling'] = 0
        " if this is the first call to this function, we also want to reset the
        " 'compilation_queued' variable, since we are the queued compilation
        if firstcall
            let g:vit_compiler_ctx['is_queued'] = 0
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
    let cmd = vitutil#PrepareArgs([compiler, flags], fnameescape(filepath))
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

    " mark as compiling
    let g:vit_compiler_ctx['is_compiling'] = 1
    " simple print
    let compiling_text = 'Compiling No. '.currentcomp.' of '.numcomps.'...'
    echo compiling_text | redraw
    " popup notification
    let win = bufwinid(a:buf)
    if win != -1
        let [row, col] = win_screenpos(win)
        let g:vit_compiler_ctx['last_popupid'] = popup_notification(
                    \ compiling_text,
                    \ {
                        \ 'highlight': 'ViTCompileMsg',
                        \ 'line': row + 1,
                        \ 'col': col + 5,
                        \ 'dragall': 1,
                    \ })
    endif
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
    " if buffer is not found, returns -1
    let errbuf = bufnr(file)
    " if no line or error is given, abort
    if empty(line) || empty(error)
        return
    endif

    " place sign
    if errbuf != -1
        " 0 for allocating new identifier
        call sign_place(0, 'ViT', 'ViTError', errbuf, #{lnum: line})
        " set signs for hover function, format is 'bufnr:line' for keys
        let g:vit_signs[errbuf.':'.line] = error
    endif
    " place in quickfix list
    let qflistdict = {'lnum': line, 'text': error, 'filename': file, 'type': 'E'}
    if errbuf != -1
        let qflistdict['bufnr'] = errbuf
        let qflistdict['module'] = bufname(errbuf)
    endif
    call setqflist([qflistdict], 'a')

    " TODO: look into printing status messages for this callback
endfunction

function vit#CompileExitCallback(exit, numcomps, buf, silent, compiler, pwd, currentcomp)
    let g:vit_compiler_ctx['is_compiling'] = 0

    if a:currentcomp < a:numcomps
        " call the function again and return
        call vit#Compile(a:buf, a:silent, a:compiler, a:pwd, a:currentcomp + 1)
        return
    endif
    if g:vit_compiler_ctx['is_queued']
        " if a compilation was queued, just call that again now and return
        let g:vit_compiler_ctx['is_queued'] = 0
        call vit#Compile(a:buf, a:silent, a:compiler, a:pwd, v:none)
        return
    endif

    " handle success message
    let strexit = string(a:exit)
    if a:exit == 0
        echohl MoreMsg | redraw
        echo '['.strexit.'] Compiled succesfully! Yay!'
        echohl None
    else
        echohl ErrorMsg | redraw
        echo '['.strexit.'] Compiled with errors... :('
        echohl None
    endif
    " update last popup
    if g:vit_compiler_ctx['last_popupid'] != -1
        call popup_setoptions(
                    \ g:vit_compiler_ctx['last_popupid'],
                    \ {
                        \ 'highlight': (a:exit == 0) ? 'ViTSuccMsg' : 'ViTErrMsg',
                    \ })
        let g:vit_compiler_ctx['last_popupid'] = -1
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
    let funcname = 'ViTNewCommandSub_'.id.'_'.a:name

    " ~~~~~~~~~~ command function
    function! {funcname}(mode = 'i', col = 1) range closure
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
            let [cstart, cend] = [1, -1]
        elseif a:mode == 'v'
            " character insert mode
            let [cstart, cend] = [col("'<"), col("'>") + 1]
            " possibly flip start and end
            if cstart > cend | let [cstart, cend] = [cend, cstart] | endif
        else
            throw 'ViT: Unknown mode "'.a:mode.'".'
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
                    \ 0, -1, a:numargs, a:argname, a:argdefault, a:argcomplete)
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

    " ~~~~~~~~~~ save into our list
    let firstline = get(a:textbefore, 0, '')
    if len(firstline) > 0
        let preview = a:inlinemode
                    \ ? join(a:textbefore, "\n").'*'.join(a:textafter, "\n")
                    \ : join(a:textbefore + ['<*>'] + a:textafter, "\n")
        let template_dict = {
                    \ 'name': a:name, 'keybind': a:keybind, 'firstline': firstline,
                    \ 'inlinemode': a:inlinemode, 'preview': preview,
                    \ 'funcname': funcname}
        call add(g:vit_templates, template_dict)
    endif
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

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ COMPLETION ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

" This function returns the completion results given the current cursor position.
function vit#Complete()
    setlocal completeopt+=popup
    " get suggestions based on typed in word
    let [typedin, startcol, endcol] = vitutil#GetWordUnderCursor()
    " in the newer versions of vim 'user_data' can be any type! yay!!!
    let suggestions = mapnew(g:vit_templates, {_, tdict -> {
                        \ 'word': tdict['firstline'],
                        \ 'kind': tdict['inlinemode'] ? 'i' : '',
                        \ 'info': tdict['preview'],
                        \ 'user_data': {
                            \ 'vit': 1,
                            \ 'startcol': startcol,
                            \ 'endcol': startcol + strlen(tdict['firstline']),
                            \ 'funcname': tdict['funcname']
                            \ },
                    \ }})
    let GetSortedSuggestions = {t -> matchfuzzy(suggestions, t, {'key': 'word'})}
    let sorted_suggestions = GetSortedSuggestions(typedin)
    " if the string has a \ in the middle somewhere, cut off that last part and match that
    " as well
    if typedin =~ '.\+\\.*'
        let lastpart = strpart(typedin, strridx(typedin, '\'))
        let sorted_suggestions += GetSortedSuggestions(lastpart)
    endif
    " present suggestions
    call complete(startcol + 1, sorted_suggestions)
endfunction

" This function is called when a completion is done. It will then determine whether to run
" a templating function or not.
function vit#OnComplete()
    let completed_item = get(v:completed_item, 0, {})
    let user_data = get(v:completed_item, 'user_data', {})
    "check if we should process this at all
    if !(type(user_data) is v:t_dict) || !has_key(user_data, 'vit')
        return
    endif
    " first of all replace the current line with all its contents but removing the
    " text inserted during completion
    let lnum    = line('.')
    let oldline = getline(lnum)
    let newline = strpart(oldline, 0, user_data['startcol'])
                \ .strpart(oldline, user_data['endcol'])
    call setline(lnum, newline)
    " now we just call the function we referenced and the templating begins
    let Function = function(user_data['funcname'])
    call Function('i', user_data['startcol'] + 1)
endfunction

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ FILE TREE ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

function vit#ResetRootFile(buf)
    let buf = bufname(a:buf)
    call vitutil#ResetVar(buf, 'vit_file_tree', s:MakeFileNode(buf))
endfunction

function vit#AddParentFile(buf, filename)
    call vitnode#AddParentNode(s:GetRootNode(a:buf), s:MakeFileNode(a:filename))
endfunction

function vit#GetRootFile(buf)
    let data = get(s:GetRootNode(a:buf), 'data', v:none)
    if data is v:none | return v:none | endif
    return vitutil#PrepareFname(data, 1)
endfunction

function s:GetRootNode(buf)
    let node = vitutil#GetVar(bufname(a:buf), 'vit_file_tree')
    " skip this loop if node is none
    while !(node is v:none) && (len(node['parents']) > 0)
        if len(node['parents']) > 1
            echohl ErrorMsg
            echomsg 'ViT: A file tree node cannot have multiple parents. '
                        \ .'Offending node is '.vitnode#ToString(node, 1)
            echohl None
        endif
        let node = node['parents'][0]
    endwhile
    if node is v:none
        echohl ErrorMsg
        echomsg 'ViT: This buffer has no root file set. Something went wrong with ViT...'
        echohl None
    endif
    return node
endfunction

function s:MakeFileNode(filename)
    return vitnode#Node(vitutil#PrepareFname(a:filename, 1))
endfunction

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ MODELINE ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

" Sets the vit_compiler, vit_num_compilations variable, and what larger file tree this
" file is included in based on the following syntax:
"
"     Modeline      ::= ^ <ViTPrefix> \s+ ( <Compilation> | <Included> ) \s* $ ;
"     ViTPrefix     ::= .* '%' \s* 'ViT'
"
"     Compilation   ::= <Numcomps> ( \s+ <OnWrite> )?
"                           ( \s+ <Compiler> ( \s+ <CompilerFlags> )? )? ;
"     OnWrite       ::= 'onwrite' | 'on-write' | 'onsave' | 'on-save' ;
"     Numcomps      ::= ( 'x' \d\+ ) | ( \d\+ 'x' ) ;
"     Compiler      ::= '-' | \w+ ;
"     CompilerFlags ::= '-' | .+ ;
"
"     Included      ::= 'included in' \s+ <File> ;
"     File          ::= .+ ;
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
    call vitutil#ResetVar(buf, 'vit_compiler')
    call vitutil#ResetVar(buf, 'vit_compile_on_write')
    " call the work-horse
    call vitmodeline#Parse(a:buf, buf, 0, a:numlines, a:maxdepth)
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

" Returns the current ViT statusline of this buffer. This only works if the internal
" function 's:UpdateStatusline' has been called beforehand, typically when opening or
" compiling the document.
function vit#GetStatusline(buf = v:none, suppress = 0)
    let buf = (a:buf is v:none) ? bufname() : a:buf
    let statusline = trim(vitutil#GetVar(buf, 'vit_statusline', v:none))
    if statusline is v:none || len(statusline) < 1
        if !a:suppress
            echohl Error
            echomsg 'ViT: No statusline found, has the document "'.bufname(buf)
                        \ .'" been compiled yet?'
            echohl None
        endif
        return ''
    endif
    return statusline
endfunction

" Updates the current ViT statusline of this buffer by running a job.
function s:UpdateStatusline(buf, cmdpat, filepath)
    if a:cmdpat is v:none || len(trim(a:cmdpat)) < 1 | return | endif

    let cmd = vitutil#PrepareArgs([a:cmdpat], fnameescape(a:filepath))
    call vitutil#ResetVar(a:buf, 'vit_statusline', '')
    " ugly hack function callback, we get the current value and then concat the msg
    function! s:ConcatStatusline(msg) closure
        let vit_statusline = vitutil#GetVar(a:buf, 'vit_statusline', '')
        call setbufvar(a:buf, 'vit_statusline', vit_statusline.a:msg)
        redrawstatus
    endfunction
    let s:sl_currjob = job_start(cmd, {'out_cb': {_, msg -> s:ConcatStatusline(msg)}})
endfunction

" Deletes a LaTeX environment and re-indents the inside lines. This only works if the
" \begin and \end statements are on their own line.
function vit#DeleteCurrentTeXEnv()
    " save cursor pos for end
    let [clnum, ccol] = [line('.'), col('.')]
    let [envname, slnum, scol, elnum, ecol] = vitutil#CurrentTeXEnvPositions()
    if empty(envname) || (slnum >= elnum) || slnum == 0 | return | endif
    " get lines and indent them the same as the original first line
    let sindent = indent(slnum)
    let lines   = vimse#IndentLines(slice(getline(slnum, elnum), 1, -1), sindent)
    " delete and then append lines
    execute 'silent '.slnum.','.elnum.'delete'
    call append(slnum - 1, lines)
    " restore cursor pos
    call cursor(clnum - (clnum > slnum) - (clnum > elnum), ccol)
endfunction

" Changes a LaTeX environment by converting the environment name to a template variable
" '#1' and executing a template similar to ':ViTEnvironment'. Only works when \begin and
" \end statements are on their own line.
function vit#ChangeCurrentTeXEnv()
    " save cursor pos for end
    let [clnum, ccol] = [line('.'), col('.')]
    let [envname, slnum, scol, elnum, ecol] = vitutil#CurrentTeXEnvPositions()
    if empty(envname) || (slnum >= elnum) || slnum == 0 | return | endif
    " replace environment names with '#1'
    for l in [slnum, elnum]
        execute 'silent '.l.'substitute/'.vitutil#EscapeRegex(envname).'/#1/'
    endfor
    " disable highlighting just in case
    noh
    " now do templating with those #1s
    call vimse#TemplateString(slnum, elnum, scol, ecol, 1, ['Name: '])
    " restore cursor pos
    call cursor(clnum, ccol)
endfunction

" Adds or removes a '*' from the environment name.
function vit#ChangeCurrentTeXEnvStar()
    let [envname, slnum, scol, elnum, ecol] = vitutil#CurrentTeXEnvPositions()
    if empty(envname) || (slnum >= elnum) || slnum == 0 | return | endif
    " either add or remove * based on what is there already
    let newname = (envname =~ '.\+\*')
                \ ? strpart(envname, 0, len(envname) - 1)
                \ : envname.'*'
    " replace environment names with 'newname'
    for l in [slnum, elnum]
        execute 'silent '.l.'substitute'
                    \ .'/'.vitutil#EscapeRegex(envname)
                    \ .'/'.vitutil#EscapeRegex(newname).'/'
    endfor
    " disable highlighting just in case
    noh
endfunction

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ MISC UTILITY FUNCTIONS ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

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
    for [key, value] in items(vitutil#GetVar(buf, 'vit_compiler'))
        call add(strs, '    '.string(key).': '.string(value).',')
    endfor
    call add(strs, '  }')
    call add(strs, '```')
    call add(strs, '')
    call add(strs, 'Compiles on write: '
                \ .(vitutil#GetVar(buf, 'vit_compile_on_write') ? 'Yes' : 'Nope'))
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

