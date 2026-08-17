import sys
try:
    from PIL import Image
    img = Image.open('assets/images/app_icon.jpg')
    print("Format:", img.format, "Size:", img.size, "Mode:", img.mode)
    
    # Check 4 corners to see background color
    w, h = img.size
    print("Corners:", img.getpixel((0,0)), img.getpixel((w-1,0)), img.getpixel((0,h-1)), img.getpixel((w-1,h-1)))
except Exception as e:
    print(e)
