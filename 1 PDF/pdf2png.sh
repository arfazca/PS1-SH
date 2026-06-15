#!/bin/bash

# Check if a PDF file was specified as an argument
if [ -z "$1" ]; then
  # If no file was specified, print an error message and exit with a status of 1
  echo "Error: No PDF file specified."
  exit 1
fi

# Transparent PDF
# gs -dSAFER -dQUIET -dNOPLATFONTS -dNOPAUSE -dBATCH -sOutputFile="outPNG.png" -sDEVICE=pngalpha -r300 -dTextAlphaBits=4 -dGraphicsAlphaBits=4 -dUseCIEColor -dUseTrimBox "$1"

# Non-transparent PDF
gs -dSAFER -dQUIET -dNOPLATFONTS -dNOPAUSE -dBATCH -sOutputFile="outPNG.png" -sDEVICE=png16m -r300 -dTextAlphaBits=4 -dGraphicsAlphaBits=4 -dUseCIEColor -dUseTrimBox "$1"

# Use Ghostscript to convert the specified PDF file to a PNG image
# Options:
# -dSAFER: Enables safer mode, which restricts file operations and prevents scripts from being run
# -dQUIET: Suppresses routine information comments in the output
# -dNOPLATFONTS: Disables platform fonts
# -dNOPAUSE: Disables the prompt and pause at the end of each page
# -dBATCH: Causes Ghostscript to exit after processing all files
# -sOutputFile="output.png": Specifies the name of the output file

# -sDEVICE: Sets the output device. In this context, it determines the format of the output image. Here are the options:
#   -> pngmono: Generates a black-and-white PNG.
#   -> pnggray: Generates a grayscale PNG.
#   -> png16: Generates a 4-bit color PNG. This means it can use up to 16 colors.
#   -> png256: Generates an 8-bit color PNG. This means it can use up to 256 colors.
#   -> png16m: Generates a 24-bit color PNG. This means it can use up to 16 million colors. This is a non-transparent format.
#   -> pngalpha: Generates a 32-bit color PNG with an alpha channel. This means it can use up to 16 million colors plus transparency.
#   -> -> -> We're using png16m, which will generate a 24-bit color PNG without transparency.

# -r<number>: Sets the resolution in dots per inch (DPI). The number can be any positive integer. 
#   -> -r300: Sets the resolution to 300 DPI
#   -> -r72 sets the resolution to 72 DPI, -r150 sets it to 150 DPI, and so on. 
#   -> Higher numbers result in higher resolution and larger file size, while lower numbers result in lower resolution and smaller file size. 
#   -> -> -> We're using -r300, which sets the resolution to 300 DPI.

# -dTextAlphaBits=<value>: Controls the use of anti-aliasing for text. The value can be 1, 2, or 4.
#   -> 1: No anti-aliasing is used.
#   -> 2: Some anti-aliasing is used, which can help smooth the edges of text but may also make it look blurry.
#   -> 4: Maximum anti-aliasing is used, which can make text look smoother and more readable, especially at lower resolutions, but it may also increase the file size.
#   -> We're using -dTextAlphaBits=4, which sets the maximum level of anti-aliasing for text.

# -dGraphicsAlphaBits=<value>: Controls the use of anti-aliasing for graphics. The value can be 1, 2, or 4.
#   -> 1: No anti-aliasing is used.
#   -> 2: Some anti-aliasing is used, which can help smooth the edges of graphics but may also make them look blurry.
#   -> 4: Maximum anti-aliasing is used, which can make graphics look smoother, especially at lower resolutions, but it may also increase the file size.
#   -> -> -> We're using -dGraphicsAlphaBits=4, which sets the maximum level of anti-aliasing for graphics.

# -dUseCIEColor: This option tells Ghostscript to use the CIE color space for the output.
# CIE color space is a color space where colors are defined independently of their nature of creation or the device they are displayed on.
# This can help ensure that the colors in the output image match the colors in the original PDF as closely as possible.
# Note: This option may not have an effect on some output devices (like pngalpha), but it can be useful when converting a PDF with a specific color profile.

# -dUseTrimBox: This option tells Ghostscript to use the TrimBox defined in the PDF to determine the size of the output image.
# The TrimBox defines the intended dimensions of the finished page. Using the TrimBox can be useful if the PDF includes extra content like crop marks outside the main content area.
# When this option is used, the output image will be cropped to the size of the TrimBox, excluding any extra content outside this area.

# Omitting -dFirstPage and -dLastPage: By default, Ghostscript will process all pages in the PDF.
# This can be useful if you want to convert the entire PDF into a set of images, with one image per page.

# -dFirstPage=<number>: This option tells Ghostscript to start processing from the specified page number in the PDF.
#   -> The number can be any positive integer corresponding to a page in the PDF.
#   ->  -dFirstPage=1 starts processing from the first page, -dFirstPage=2 starts from the second page, and so on.
#   -> This can be useful if you only want to convert a specific range of pages from the PDF.
#   -> -> -> We're using -dFirstPage=1, which means the processing starts from the first page of the PDF.

# -dLastPage=<number>: This option tells Ghostscript to stop processing after the specified page number in the PDF.
#   -> The number can be any positive integer corresponding to a page in the PDF.
#   -> -dLastPage=1 stops processing after the first page, -dLastPage=2 stops after the second page, and so on. For example, -dLastPage=1 stops processing after the first page, -dLastPage=2 stops after the second page, and so on.
#   -> This can be useful if you only want to convert a specific range of pages from the PDF.
#   -> -> -> We're using -dLastPage=1, which means the processing stops after the last page of the PDF.