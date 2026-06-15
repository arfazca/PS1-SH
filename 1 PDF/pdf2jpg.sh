#!/bin/bash

# This script converts a PDF file to a JPEG image using Ghostscript.
# It takes a PDF file as an argument and generates a high-quality JPEG image as output.

if [ -z "$1" ]; then
  echo "Error: No PDF file specified."
  exit 1
fi

# The Ghostscript command is used to convert the PDF to JPEG.
# -dNOPAUSE: Disables the prompt and pauses between pages.
# -sDEVICE=jpeg: Sets the output device to JPEG format.
# -r200: Sets the resolution to 200 dpi.
# -dJPEGQ=100: Sets the JPEG quality to 100 (highest quality).
# -sOutputFile=outJPG.jpg: Specifies the output file name.
# "$1": The input PDF file.
# -dBATCH: Exits Ghostscript after processing.

gs -dNOPAUSE -sDEVICE=jpeg -r200 -dJPEGQ=100 -sOutputFile=outJPG.jpg "$1" -dBATCH
