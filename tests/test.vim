" Main file for testing ViT.
" Author: Marcel Simader (marcel0simader@gmail.com)
" Date: 25.02.2022
" (c) Marcel Simader 2022

" A test suite consists of many 'suite' objects which are dicts of the form
"     {'name': 'My Name', 'tests': [<test1>, <test2>, ...]}
"
" A test object consists of a dict with the form
"     {'name': 'My Name', 'runner': <function>}

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ HI GROUPS ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

highlight _ViTError ctermbg=DarkRed ctermfg=White
highlight _ViTSucc cterm=underline ctermfg=Green ctermbg=None
highlight _ViTFail cterm=underline ctermfg=DarkRed ctermbg=None

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ RUNNER ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

let g:vit_test_suites = []

function test#Run(suites = v:none)
    let suites = (a:suites is v:none) ? g:vit_test_suites : a:suites
    " execute suites
    redraw
    for suite in suites
        call s:RunSuite(suite)
    endfor
endfunction

function s:RunSuite(suite)
    if !has_key(a:suite, 'name') || !has_key(a:suite, 'tests')
        call s:Err('Invalid test suite "'.string(a:suite).'"')
        return
    endif
    " execute suite
    echomsg 'Running test suite "'.a:suite['name'].'"'.'...'
    for test in a:suite['tests']
        call s:RunTest(test, 4)
    endfor
endfunction

function s:RunTest(test, indent = 0)
    if !has_key(a:test, 'name') || !has_key(a:test, 'runner')
        call s:Err('Invalid test "'.string(a:test).'"')
        return
    endif
    " execute test
    echomsg repeat(' ', a:indent).'Running test "'.a:test['name'].'"'
    let v:errors = []
    let succ = 0
    let msgs = []
    try
        call a:test['runner']()
        let succ = empty(v:errors)
        let msgs += v:errors
    catch
        let succ = 0
        let msgs += [v:exception]
    endtry
    " write final message
    let msg = empty(msgs) ? '.' : ': '.join(msgs, '; ')
    if succ
        echohl _ViTSucc
        echomsg repeat(' ', a:indent + 4).'- Test "'.a:test['name'].'" succeeded'
    else
        echohl _ViTFail
        echomsg repeat(' ', a:indent + 4).'- Test "'.a:test['name'].'" failed'
    endif
    echon msg
    echohl None
endfunction

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ CREATORS ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

function test#RegisterSuites(suites)
    let g:vit_test_suites += a:suite
endfunction

function test#MakeSuite(name, tests = [])
    return #{name: a:name, tests: a:tests}
endfunction

function test#MakeTest(name, runner)
    return #{name: a:name, runner: a:runner}
endfunction

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ UTILS ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

function s:Err(msg, warn = 0)
    echohl _ViTError | echomsg a:msg | echohl None
endfunction

