# Baylock

Baylock is a Flutter document viewer and note-taking app for PDF, PPTX, DOCX,
XLSX/CSV, text, and image files. It supports page-specific text notes and
drawings without modifying the original document.

## Sharing a document with its notes

Use **Belgeyi notlarla paylaş** in a supported document viewer. Baylock creates
a `.baylock` package containing the original file, page note sheets, and saved
ink annotations. The original document is not changed.

The recipient can select the `.baylock` file with Baylock's **Dosya seç**
action. Baylock imports a separate copy into its own documents folder and opens
it with its page notes. To view or edit the notes, open the relevant page and
tap its notes button.
