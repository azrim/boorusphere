# Boorusphere

Boorusphere is a Flutter Android client for booru image boards. This glossary pins down the vocabulary that is specific to the app's own design.

## Language

**PostMedia**:
The single seam between the post viewer and a post's media. One widget renders the correct media kind — image, video, or unsupported — so the viewer never branches on media type itself.
_Avoid_: PostMediaView, MediaView

**RawPost**:
The engine-neutral record a search parser emits for one raw entry. A parser maps its response shape into `RawPost` fields (tags already decoded per engine) and hands it to the pipeline; it carries no `Post` concerns such as URL normalization or server binding.
_Avoid_: RawEntry, PostDraft

**buildPosts**:
The shared raw-entry → `Post` pipeline (`utils/post_pipeline.dart`). It owns the entry filter, the validity guard (needs a file and positive dimensions), per-response de-dup, URL normalization, and `Post` construction, so each search parser supplies only a mapping function.
_Avoid_: PostBuilder, PostFactory
