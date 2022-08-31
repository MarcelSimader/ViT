" Data structure for the ViT plugin.
" Author: Marcel Simader (marcel0simader@gmail.com)
" Date: 03.06.2022
" (c) Marcel Simader 2022

" Data structure formats:
"
" Node = Dict {
"     'data': Any,
"     'parents': List[Node],
"     'children': List[Node],
" }
"

function vitnode#Test()
    let a = vitnode#Node("a")
    let b = vitnode#AddChild(a, "b")
    let c = vitnode#AddChild(a, "c")
    let d = vitnode#AddChild(a, "d")

    let ca = vitnode#AddChild(c, "ca")
    call vitnode#AddParentNode(c, d)
    let cb = vitnode#AddChild(c, "cb")
    let cc = vitnode#AddChild(c, "cc")

    let cola = vitnode#Collect(c)
    let colb = vitnode#CollectUpwards(cc)
    let colc = vitnode#CollectLeftOf(c)

    call vitnode#WriteDot(a, "test1.dot", 1, '  ')

    call vitnode#RemoveNode(c)

    call vitnode#WriteDot(a, "test2.dot", 1, '  ')
    echomsg vitnode#ToString(a)
endfunction

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ NODE ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

function s:checkNode(node)
    " node type
    if type(a:node) != v:t_dict
        throw 'Node is not a dict but "'.typename(a:node).'"'
    endif
    " keys
    if !has_key(a:node, 'data') | throw 'No "data" key in node' | endif
    if !has_key(a:node, 'parents') | throw 'No "parents" key in node' | endif
    if !has_key(a:node, 'children') | throw 'No "children" key in node' | endif
    " parents type
    let parents = a:node['parents']
    if type(parents) != v:t_list
        throw '"parents" key in node is not a list but "'.typename(parents).'"'
    endif
    " children type
    let children = a:node['children']
    if type(children) != v:t_list
        throw '"children" key in node is not a list but "'.typename(children).'"'
    endif
endfunction

" Creates a new node with data 'data'.
" Arguments:
"   - data, the data of the 'data' to put in the data of the 'data' attribute
function vitnode#Node(data)
    return {'data': a:data, 'children': [], 'parents': []}
endfunction

" ~~~~~~~~~~~~~~~~~~~~ INSERTIONS ~~~~~~~~~~~~~~~~~~~~

" ~~~~~~~~~~ children

" Inserts new node with 'data' as child of 'dest' at position 'index'. See ':h insert()'.
" Arguments:
"   - dest, the node to modify
"   - index, the position of the insertion
"   - data, the data of the new node to insert
" Returns: the new node
function vitnode#InsertChild(dest, index, data)
    return vitnode#InsertChildNode(a:dest, a:index, vitnode#Node(a:data))
endfunction

" Inserts node 'node' as child of 'dest' at position 'index'. See ':h insert()'.
" Arguments:
"   - dest, the node to modify
"   - index, the position of the insertion
"   - node, the node to insert
" Returns: the given node
function vitnode#InsertChildNode(dest, index, node)
    call s:checkNode(a:dest)
    call s:checkNode(a:node)
    call insert(a:dest['children'], a:node, a:index)
    call add(a:node['parents'], a:dest)
    return a:node
endfunction

" Adds new node with 'data' as child of 'dest'.
" Arguments:
"   - dest, the node to modify
"   - data, the data of the new node to add
" Returns: the new node
function vitnode#AddChild(dest, data)
    return vitnode#AddChildNode(a:dest, vitnode#Node(a:data))
endfunction

" Adds node 'node' as child of 'dest'.
" Arguments:
"   - dest, the node to modify
"   - node, the node to add
" Returns: the given node
function vitnode#AddChildNode(dest, node)
    call s:checkNode(a:dest)
    call s:checkNode(a:node)
    call add(a:dest['children'], a:node)
    call add(a:node['parents'], a:dest)
    return a:node
endfunction

" ~~~~~~~~~~ parents

" Inserts new node with 'data' as parent of 'dest' at position 'index'. See ':h insert()'.
" Arguments:
"   - dest, the node to modify
"   - index, the position of the insertion
"   - data, the data of the new node to insert
" Returns: the new node
function vitnode#InsertParent(dest, index, data)
    return vitnode#InsertParentNode(a:dest, a:index, vitnode#Node(a:data))
endfunction

" Inserts node 'node' as parent of 'dest' at position 'index'. See ':h insert()'.
" Arguments:
"   - dest, the node to modify
"   - index, the position of the insertion
"   - node, the node to insert
" Returns: the given node
function vitnode#InsertParentNode(dest, index, node)
    call s:checkNode(a:dest)
    call s:checkNode(a:node)
    call insert(a:dest['parents'], a:node, a:index)
    call add(a:node['children'], a:dest)
    return a:node
endfunction

" Adds new node with 'data' as parent of 'dest'.
" Arguments:
"   - dest, the node to modify
"   - data, the data of the new node to add
" Returns: the new node
function vitnode#AddParent(dest, data)
    return vitnode#AddParentNode(a:dest, vitnode#Node(a:data))
endfunction

" Adds node 'node' as parent of 'dest'.
" Arguments:
"   - dest, the node to modify
"   - node, the node to add
" Returns: the given node
function vitnode#AddParentNode(dest, node)
    call s:checkNode(a:dest)
    call s:checkNode(a:node)
    call add(a:dest['parents'], a:node)
    call add(a:node['children'], a:dest)
    return a:node
endfunction

" ~~~~~~~~~~~~~~~~~~~~ DELETIONS ~~~~~~~~~~~~~~~~~~~~

" Removes 'child' from the children of 'node'.
function s:removeFromChildren(node, child)
    let oldidx = -1
    while 1
        let idx = index(a:node['children'], a:child)
        if idx == -1 | break | end
        call remove(a:node['children'], idx)
        let oldidx = idx
    endwhile
    return oldidx
endfunction

" Removes 'parent' from the parents of 'node'.
function s:removeFromParents(node, parent)
    let oldidx = -1
    while 1
        let idx = index(a:node['parents'], a:parent)
        if idx == -1 | break | end
        call remove(a:node['parents'], idx)
        let oldidx = idx
    endwhile
    return oldidx
endfunction

" Removes node 'node' from its graph.
" Arguments:
"   - node, the node to remove
function vitnode#RemoveNode(node)
    call s:checkNode(a:node)
    let parents = copy(a:node['parents'])
    let children = copy(a:node['children'])
    " remove references and fill gap in graph
    for parent in parents
        let idx = s:removeFromChildren(parent, a:node)
        call s:removeFromParents(a:node, parent)
        if idx != -1 | call extend(parent['children'], children, idx) | endif
    endfor
    for child in children
        let idx = s:removeFromParents(child, a:node)
        call s:removeFromChildren(a:node, child)
        if idx != -1 | call extend(child['parents'], parents, idx) | endif
    endfor
endfunction

" ~~~~~~~~~~~~~~~~~~~~ COLLECTION ~~~~~~~~~~~~~~~~~~~~

function s:collect(node, nodemap, datamap, seen)
    " make sure we have not visited this node yet
    if index(a:seen, a:node) == -1 | call add(a:seen, a:node) | else | return [] | endif
    call s:checkNode(a:node)
    " do traversing
    let out = []
    for newnode in a:nodemap(a:node)
        let out += s:collect(newnode, a:nodemap, a:datamap, a:seen)
    endfor
    let out += [a:datamap(a:node['data'])]
    return out
endfunction

" Walks downwards from node 'root' and collects all 'data' elements in an array. Argument
" 'datamap' can be given to apply to every collected element before adding it to said
" array. This argument is a function taking the datum as argument and returning the
" transformed element.
" Arguments:
"   - root, the node to start traversal on
"   - [datamap,] the mapping to apply to each datum, defaults to the identity
"       function '{d -> d}'
function vitnode#Collect(root, datamap = {d -> d})
    return s:collect(a:root, {node -> node['children']}, a:datamap, [])
endfunction

" See 'vitnode#Collect()'. Same functionality but walking upwards from node 'root'.
function vitnode#CollectUpwards(leaf, datamap = {d -> d})
    return s:collect(a:leaf, {node -> node['parents']}, a:datamap, [])
endfunction

function s:collectLeftOf(node, datamap, pivot, seen)
    " make sure we have not visited this node yet
    if index(a:seen, a:node) == -1 | call add(a:seen, a:node) | else | return [] | endif
    call s:checkNode(a:node)
    " do traversing
    let out = []
    for child in a:node['children']
        if child == a:pivot | break | endif
        let out += s:collectLeftOf(child, a:datamap, a:pivot, a:seen)
    endfor
    let out += [a:datamap(a:node['data'])]
    for parent in a:node['parents']
        let out += s:collectLeftOf(parent, a:datamap, a:node, a:seen)
    endfor
    return out
endfunction

" Performs a graph traversal starting at 'node' but only collects data from nodes which
" are 'left of' node 'node' in the graph. As in 'vitnode#Collect()', the 'datamap'
" argument can be used to apply a transformation to any collected datum. As example,
" consider the case below:
"
"        A
"        |
"     +--+--+
"     |  |  |
"     B  C  D
"        |
"        +--+
"        |  |
"        E  F
"
" If we choose node 'C' as 'node' we would first pick up 'E', then 'F', then 'C' itself,
" then 'B', and finally 'A'.
"
" Generally all data below node 'C' is collected. Also all nodes above 'C' are collected.
" But when we are 'at the same level' as node 'C' (i.e. node 'C' is contained in either
" the 'parents' or 'children' of a node), we only collect up until we reach node 'C'.
"
function vitnode#CollectLeftOf(node, datamap = {d -> d})
    return s:collectLeftOf(a:node, a:datamap, a:node, [])
endfunction

" ~~~~~~~~~~~~~~~~~~~~ CONVERSIONS ~~~~~~~~~~~~~~~~~~~~

function s:toString(node, multiline, indent)
    call s:checkNode(a:node)
    let out = [string(a:node['data'])]
    let haschildren = len(a:node['children']) > 0
    if haschildren | let out[0] .= '->{' | endif
    for child in a:node['children']
        let rec = s:toString(child, a:multiline, a:indent)
        let out += a:multiline ? map(rec, {_, v -> a:indent.v}) : rec
    endfor
    if haschildren | let out += ['}'] | endif
    return out
endfunction

" Converts graph starting at 'node' to a string.
" Arguments:
"   - node, the node to start traversal on
"   - [multiline,] can be set to true to enable multiple lines in the output, defaults
"       to 0
function vitnode#ToString(node, multiline = 0)
    let out = s:toString(a:node, a:multiline, '  ')
    return a:multiline ? out : join(out, ' ')
endfunction

function s:WriteDot(node, indent, color, ctx = {'visited': [], 'name': [], 'i': 0})
    function! s:lookupNode(node, indent, color, ctx)
        call s:checkNode(a:node)
        " handle name based on == comparisons
        let filtered = filter(copy(a:ctx['name']), {_, v -> v[0] == a:node})
        if len(filtered) > 0
            let i = filtered[0][1]
        else
            let i = a:ctx['i']
            let a:ctx['name'] += [[a:node, i]]
            let a:ctx['i'] += 1
        endif
        let color = (index(a:color, a:node['data']) == -1) ? '' : ', color = "red"'
        return [i, [a:indent.i.' [label = "'.string(a:node['data']).'"'.color.']']]
    endfunction
    " check if we already visited this node
    if index(a:ctx['visited'], a:node) == -1
        let a:ctx['visited'] += [a:node]
    else
        return []
    end
    " write dot
    let out = []
    let [i, iout] = s:lookupNode(a:node, a:indent, a:color, a:ctx)
    let out += iout
    for child in a:node['children']
        let [j, jout] = s:lookupNode(child, a:indent, a:color, a:ctx)
        let out += jout
        let out += s:WriteDot(child, a:indent, a:color, a:ctx)
        let out += [a:indent.i.' -> '.j]
    endfor
    for parent in a:node['parents']
        let [j, jout] = s:lookupNode(parent, a:indent, a:color, a:ctx)
        let out += jout
        let out += [a:indent.i.' -> '.j]
    endfor
    return out
endfunction

" Writes the graph starting at node 'node' to a GraphViz dot file called 'fname'.
" Arguments:
"   - node, the node to start traversal on
"   - fname, the file name
"   - [overwrite,] sets whether or not to overwrite existing files, defaults to 0
"   - [indent,] sets the indent to be used, defauls to '  '
"   - [color,] a list of nodes which will be marked in color in the output
" Returns: the array of lines that was written to the file 'fname'
function vitnode#WriteDot(node, fname, overwrite = 0, indent = '  ', color = [])
    let out = ['digraph {']
    let out += s:WriteDot(a:node, a:indent, a:color, {'visited': [], 'name': [], 'i': 0})
    let out += ['}']
    if a:overwrite || !filereadable(a:fname)
        call writefile(out, a:fname)
    else
        throw 'File "'.a:fname.'" already exists'
    endif
    return out
endfunction

