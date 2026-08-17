from PIL import Image

def make_transparent(input_path, output_path, threshold=240):
    img = Image.open(input_path).convert("RGBA")
    datas = img.getdata()

    newData = []
    for item in datas:
        # If pixel is close to white, make it transparent
        if item[0] > threshold and item[1] > threshold and item[2] > threshold:
            newData.append((255, 255, 255, 0))
        else:
            newData.append(item)

    img.putdata(newData)
    img.save(output_path, "PNG")

make_transparent("assets/images/app_icon.jpg", "assets/images/app_icon.png")
