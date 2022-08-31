" Modeline parsing for the ViT Vim plugin.
" Author: Marcel Simader (marcel0simader@gmail.com)
" Date: 29.08.2022
" (c) Marcel Simader 2022

" This function utlilizes a context dictionary to split its functionality amongs smaller
" functions:
"
" Context = Dict {
"     'buf': the original buffer,
"     'file': the file to currently read lines from,
"     'depth': how deep we have traversed the files,
"     'numlines': the number of lines to check for the header in each file,
"     'maxdepth': the maximum depth to traverse,
"     'line': the line currently being looped,
"     'linenr': the line number of the current line,
"     'did_included': whether this was parsed already,
"     'did_compiler': -"-,
" }
"

" The regex starting a modeline.
let s:modeline_pre = '^.*%\s*ViT\s\+'
" The regex at the end of a modeline.
let s:modeline_suf = '\s*$'

" Recursive work-horse of vit#ParseModeline().
" Arguments:
"   buf, the buf to set options in (most likely current buffer)
"   file, the file to read lines from
"   depth, the current recursive depth
"   numlines, the number of lines to read from 'file'
"   maxdepth, the number of recursive calls to perform before giving up
function vitmodeline#Parse(buf, file, depth, numlines, maxdepth)
    " context as specified at start of file
    let ctx = {
                \ 'buf': a:buf,
                \ 'file': a:file,
                \ 'depth': a:depth,
                \ 'numlines': a:numlines,
                \ 'maxdepth': a:maxdepth,
                \ 'line': v:none,
                \ 'linenr': v:none,
                \ 'did_included': 0,
                \ 'did_compiler': 0,
                \ }
    return s:Parse(ctx)
endfunction

function s:Parse(ctx)
    if a:ctx['depth'] >= a:ctx['maxdepth']
        echohl ErrorMsg
        echomsg 'ViT: Reached max depth of '.a:ctx['maxdepth'].' while parsing modeline.'
        echohl None
        return
    endif

    let linenr = 0
    " read in text-mode so ''
    for line in readfile(a:ctx['file'], '', a:ctx['numlines'])
        let linenr += 1
        " update context
        let a:ctx['line']   = line
        let a:ctx['linenr'] = linenr
        " pre-order traversal
        if s:IncludedIn(a:ctx)
            continue
        endif
        " now post-order traversal
        if s:Compiler(a:ctx)
            continue
        endif
    endfor
endfunction

" These functions are called in 's:Parse' and return 0 to keep execution going in the main
" function, or 1 to skip to the next line in the main file loop.

function s:IncludedIn(ctx)
    let match = matchlist(a:ctx['line'],
                \ s:modeline_pre
                \ .'included in\s\+\(.\+\)'
                \ .s:modeline_suf)
    if empty(match) | return 0 | endif
    if a:ctx['did_included']
        echohl ErrorMsg
        echomsg 'ViT: Found duplicated included-in modeline in line '
                    \ .a:ctx['linenr'].' ('.a:ctx['file'].'):'
        echomsg '-- '.a:ctx['line']
        echohl None
        return 0
    else
        let a:ctx['did_included'] = 1
    endif
    let includedin = match[1]
    if empty(includedin) | return 0 | endif

    " get actual path of the file
    try
        let file = vitutil#PrepareFname(includedin, 1)
        " modify file tree
        call vit#AddParentFile(a:ctx['buf'], file)
        " parse modeline of includedin file
        let nctx = copy(a:ctx)
        let nctx['depth'] += 1
        let nctx['file'] = file
        call s:Parse(nctx)
        " success
        return 1
    catch /ViT.*/
        echohl ErrorMsg
        echomsg 'ViT: Unable to handle included-in file "'.includedin.'"! '
                    \ .'Maybe it does not exist!'
        echomsg '-- '.v:exception
        echohl None
        return 0
    endtry
endfunction

function s:Compiler(ctx)
    let match = matchlist(a:ctx['line'],
                \ s:modeline_pre
                \ .'\%(x\=\(\d\+\)x\=\)'
                \ .'\%(\s\+\(onwrite\|on-write\|onsave\|on-save\)\)\='
                \ .'\%(\s\+\(\%(\w\+\)\|\-\)'
                    \ .'\%(\s\+\(\%(.\+\)\|-\)\)\=\)\='
                \ .s:modeline_suf)
    if empty(match) | return 0 | endif
    if a:ctx['did_compiler']
        echohl ErrorMsg
        echomsg 'ViT: Found duplicated compiler modeline in line '
                    \ .a:ctx['linenr'].' ('.a:ctx['file'].'):'
        echomsg '  '.a:ctx['line']
        echohl None
        return 0
    else
        let a:ctx['did_compiler'] = 1
    endif

    let [numcomps, onwrite, comp, compflags]
            \ = [match[1], match[2], match[3], match[4]]
    " handle logic where we set both comp and compflags to '-' if they are empty
    " in case the user wants to just write '% ViT x3' without resetting the
    " compiler and its flags
    if empty(comp) && empty(compflags)
        let [comp, compflags] = ['-', '-']
    endif
    let vit_compiler = vitutil#GetVar(a:ctx['buf'], 'vit_compiler')
    " num compilations
    if !empty(numcomps)
        let vit_compiler['numcomps'] = str2nr(numcomps)
    endif
    " on-write
    if !empty(onwrite)
        call setbufvar(a:ctx['buf'], 'vit_compile_on_write', 1)
    endif
    " compiler
    if comp != '-'
        let vit_compiler['compiler'] = comp
    endif
    " compiler flags
    if compflags != '-'
        let vit_compiler['flags'] = compflags
    endif
    " success
    return 1
endfunction

