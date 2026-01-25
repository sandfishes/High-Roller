package Handle_Map

import "base:runtime"

// TODO switch to dynamic handle map with backing allocator for faster looping
// Just set the latest idx.
Handle_Map :: struct($T: typeid, $HT: typeid, $N: u32) {
	items: [N]T,
	num_items: u32,
	next_unused: u32,
	unused_items: [N]u32,
	num_unused: u32,
        up_to: u32,
        gen: u32,
        delete_func: proc(^T, runtime.Allocator),
}

Handle :: struct {
        idx: u32,
        gen: u32,
}

init_handle_map :: proc(hm: ^Handle_Map($T, $HT, $N))
{
        hm.next_unused = 1
        hm.num_unused = N-1
        for _, idx in hm.unused_items[1:N] {
                hm.unused_items[idx] = u32(idx)+1
                // 1->2, 2->3 etc.
        }
}

add :: proc(hm: ^Handle_Map($T, $HT, $N), v: T
) -> (HT)
{
        if hm.num_unused == 0 {
                return HT{}
        }
        v := v
        v.handle = HT{idx = hm.next_unused, gen = hm.gen}
        hm.gen += 1
        hm.items[hm.next_unused] = v
        next := hm.unused_items[hm.next_unused]
        hm.unused_items[hm.next_unused] = 0 // Mark this slot as filled.
        hm.next_unused = next
        if v.handle.idx > hm.up_to {
                hm.up_to = v.handle.idx
        }
        return v.handle
}

delete :: proc(hm: ^Handle_Map($T, $HT, $N), h: HT) {
        item := hm.items[h.idx]
        if item.handle.idx == 0 || item.handle.gen != h.gen {
                return // item is already deleted or replaced
        }
        item.handle.idx = 0
        hm.unused_items[h.idx] = hm.next_unused
        hm.next_unused = h.idx
        hm.delete_func(&hm.items[h.idx], runtime.default_allocator())
}

get :: proc(hm: Handle_Map($T, $HT, $N), h:HT
) -> T 
{
        item := hm.items[h.idx]
        if item.handle != h {
                panic("Tried to retrieve invalid handle")
        }
        return item
} 

get_pointer :: proc(hm: ^Handle_Map($T, $HT, $N), h:HT
) -> ^T 
{
       item := hm.items[h.idx]
        if item.handle != h {
                panic("Tried to retrieve invalid handle")
        }
        return &hm.items[h.idx]
}

active_slice :: proc(hm: ^Handle_Map($T, $HT, $N)
) -> []T
{
        return hm.items[1:hm.up_to]
}
