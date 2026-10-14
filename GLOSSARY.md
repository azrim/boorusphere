# Boorusphere

Boorusphere is a Flutter Android client for booru image boards. This glossary pins down the vocabulary that is specific to the app's own design.

## Language

**PostMedia**:
The single seam between the post viewer and a post's media. One widget renders the correct media kind — image, video, or unsupported — so the viewer never branches on media type itself.
_Avoid_: PostMediaView, MediaView
