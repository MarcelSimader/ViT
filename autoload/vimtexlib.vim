" General 'library' functions for the VimTeXtended plugin.
" Author: Marcel Simader (marcel0simader@gmail.com)
" Date: 15.12.2021
" (c) Marcel Simader 2021

" Returns the indent of argument 'str'. It takes into account
" spaces and tabs, where tabs are counted by the value returned
" by the 'shiftwidth()' function.
function vimtexlib#StrIndent(str)
    " remove spaces from beginning and count to get indent
    let [str, indent] = [a:str, 0]
    while !empty(str) && (str[0] == ' ' || str[0] == "\t")
        let indent += (str[0] == ' ') ? (1) : (shiftwidth())
        let str = str[1:]
    endwhile
    return indent
endfunction

" Indents the lines in argument 'lines' from index start to end.
" Examples:
" 1.)
" | ABC 123                    |     ABC 123
" |     ABC 123       --->     |         ABC 123
" |      TTT        indent=4   |          TTT
" | ABC                        |     ABC
" 2.)
" |      ABC 123               |    ABC 123
" |   ABC 123         --->     | ABC 123
" |   TTT           indent=0   | TTT
" |    ABC                     |  ABC
" Arguments:
"   lines, an array of lines
"   indent, the number of spaces to indent
"   [start,] defaults to '0', the line to start on
"   [end,] defaults to 'len(lines) - 1', the line to end on
" Returns:
"   The indented lines as new list.
function vimtexlib#IndentLines(lines, indent, start = 0, end = len(a:lines) - 1)
    " early abort
    if a:end < a:start || a:indent < 0
        return a:lines
    endif
    " get smallest indent in lines
    let minindent = min(map(a:lines[a:start:a:end], 'vimtexlib#StrIndent(v:val)'))
    " actual indenting by adding an offset to all (trimmed) strings
    " that makes the least indented line level with a:indent
    for i in range(a:start, a:end)
        let indentstr = repeat(' ', vimtexlib#StrIndent(a:lines[i]) + (a:indent - minindent))
        let a:lines[i] = indentstr.trim(a:lines[i])
    endfor
    return a:lines
endfunction

" Inserts the lines in argument 'lines' with indent of 'indent'
" (see 'vimtexlib#IndentLines') at position 'lnum'. Line 'lnum'
" is overwritten, and the rest of the lines are inserted after it.
" Returns:
"   The end position of the cursor after the insert.
function vimtexlib#SmartInsert(lnum, lines, indent)
    call vimtexlib#IndentLines(a:lines, a:indent)
    " set first line
    call setline(a:lnum, get(a:lines, 0, ''))
    " insert other lines
    for i in range(1, len(a:lines) - 1)
        call append(a:lnum + i - 1, get(a:lines, i, ''))
    endfor
    return [a:lnum + len(a:lines), strlen(get(a:lines, -1, '')) + 1]
endfunction

" Surrounds the lines given by 'lstart', 'lend', with the column
" offsets given by 'cstart', 'cend' with the text 'textbefore' and
" 'textafter'. When 'middleindent' is set to a non-negative value,
" the surrounded lines are indented by that number (see
" 'vimtexlib#IndentLines').
" Arguments:
"   lstart, the start line in the current buffer
"   lend, the end line in the current buffer
"   cstart, the start column in the current buffer
"   cend, the end column in the current buffer
"   textbefore, the text to appear before '[lstart, cstart]'
"   textafter, the text to appear after '[lend, cend]'
"   [middleindent,] when non-negative, sets the indent of lines
"     between 'lstart' and 'lend'
" Returns:
"   The end position of the cursor after the insert.
function vimtexlib#SmartSurround(lstart, lend, cstart, cend,
            \ textbefore, textafter, middleindent = -1)
    let startindent = indent(a:lstart)
    " construct lines
    if a:lend - a:lstart <= 0
        let middle = [trim(getline(a:lstart))]
        " ~~~~~~~~~~
        " (L) [ ]
        let lines = [strpart(middle[0], 0, a:cstart - startindent - 1)
                    \ .get(a:textbefore, 0, '')]
        " [ ] append
        let lines += a:textbefore[1:]
        " [ ] (I) [ ] concat
        let lines[-1] .= strpart(middle[0], a:cstart - startindent - 1, a:cend - a:cstart)
                    \ .get(a:textafter, 0, '')
        " [ ] append
        let lines += a:textafter[1:]
        " [ ] (R) concat
        let lines[-1] .= strpart(middle[0], a:cend - startindent - 1, 999999)
    else
        let middle = getline(a:lstart, a:lend)
        " ~~~~~~~~~~
        " (LL) [ ]
        let lines = [strpart(middle[0], 0, a:cstart - 1)
                    \ .get(a:textbefore, 0, '')]
        " [ ] append
        let lines += a:textbefore[1:]
        " [ ] (LR) concat
        let lines[-1] .= strpart(middle[0], a:cstart - 1, 999999)
        "     ((I)) append
        let lines += middle[1:-2]
        "     (RL) [ ] concat
        let lines += [strpart(middle[-1], 0, a:cend - 1)]
        let lines[-1] .= get(a:textafter, 0, '')
        " [ ] append
        let lines += a:textafter[1:]
        " [ ] (RR) concat
        let lines[-1] .= strpart(middle[-1], a:cend - 1, 999999)
    endif
    " indent
    if a:middleindent >= 0
        call vimtexlib#IndentLines(lines, a:middleindent, 1, len(lines) - 2)
    endif
    " delete lines so we don't copy the middle ones
    call deletebufline(bufname(), a:lstart + 1, a:lend)
    " set and return final pos
    return SmartInsert(a:lstart, lines, startindent)
endfunction

