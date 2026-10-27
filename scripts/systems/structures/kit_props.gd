class_name StructureKitProps
extends RefCounted
## Kit pieces for small points of interest: wells, carts, fences, haystacks, cairns, signposts (W8-P).
## StructureBuilder.make_piece falls through to make() for any kind it does not know. Return a piece
## dictionary like StructureKit's ({kind, mesh, shapes, verts}) for a kind this file owns, {} otherwise.
## Build with StructureKit.builder(mat, name) so tiling and UV offsets match the rest of the kit.


static func make(kind: String, _p: Dictionary, _name: String = "") -> Dictionary:
	match kind:
		_:
			return {}
