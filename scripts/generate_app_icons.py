import os
from PIL import Image, ImageDraw

def create_mininote_icon(size):
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    scale = size / 128.0

    # Background rounded rectangle #2C001E (Aubergine / Ubuntu Purple)
    radius = int(20 * scale)
    draw.rounded_rectangle([0, 0, size, size], radius=radius, fill='#2C001E')

    # Top title bar #FFFFFF
    x1, y1, x2, y2 = int(22 * scale), int(50 * scale), int(106 * scale), int(60 * scale)
    r1 = int(5 * scale)
    draw.rounded_rectangle([x1, y1, x2, y2], radius=r1, fill='#FFFFFF')

    # Line 2 #B8A8B3
    x1, y1, x2, y2 = int(22 * scale), int(72 * scale), int(106 * scale), int(80 * scale)
    r2 = int(4 * scale)
    draw.rounded_rectangle([x1, y1, x2, y2], radius=r2, fill='#B8A8B3')

    # Line 3 #B8A8B3
    x1, y1, x2, y2 = int(22 * scale), int(88 * scale), int(78 * scale), int(96 * scale)
    r3 = int(4 * scale)
    draw.rounded_rectangle([x1, y1, x2, y2], radius=r3, fill='#B8A8B3')

    return img

def main():
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    flutter_dir = os.path.join(base_dir, 'flutter_app')

    # 1. Android Icons
    android_res = os.path.join(flutter_dir, 'android', 'app', 'src', 'main', 'res')
    android_sizes = {
        'mipmap-mdpi': 48,
        'mipmap-hdpi': 72,
        'mipmap-xhdpi': 96,
        'mipmap-xxhdpi': 144,
        'mipmap-xxxhdpi': 192,
    }
    for folder, size in android_sizes.items():
        folder_path = os.path.join(android_res, folder)
        os.makedirs(folder_path, exist_ok=True)
        icon = create_mininote_icon(size)
        icon.save(os.path.join(folder_path, 'ic_launcher.png'), 'PNG')
    print("Generated Android icons")

    # 2. Windows Icon (.ico)
    win_icon_path = os.path.join(flutter_dir, 'windows', 'runner', 'resources', 'app_icon.ico')
    os.makedirs(os.path.dirname(win_icon_path), exist_ok=True)
    ico_sizes = [256, 128, 64, 48, 32, 16]
    ico_images = [create_mininote_icon(s) for s in ico_sizes]
    ico_images[0].save(win_icon_path, format='ICO', sizes=[(s, s) for s in ico_sizes])
    print("Generated Windows icon")

    # 3. macOS Icons
    macos_appicon = os.path.join(flutter_dir, 'macos', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset')
    macos_sizes = {
        'app_icon_16.png': 16,
        'app_icon_32.png': 32,
        'app_icon_64.png': 64,
        'app_icon_128.png': 128,
        'app_icon_256.png': 256,
        'app_icon_512.png': 512,
        'app_icon_1024.png': 1024,
    }
    os.makedirs(macos_appicon, exist_ok=True)
    for filename, size in macos_sizes.items():
        icon = create_mininote_icon(size)
        icon.save(os.path.join(macos_appicon, filename), 'PNG')
    print("Generated macOS icons")

    # 4. iOS Icons
    ios_appicon = os.path.join(flutter_dir, 'ios', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset')
    ios_sizes = {
        'Icon-App-20x20@1x.png': 20,
        'Icon-App-20x20@2x.png': 40,
        'Icon-App-20x20@3x.png': 60,
        'Icon-App-29x29@1x.png': 29,
        'Icon-App-29x29@2x.png': 58,
        'Icon-App-29x29@3x.png': 87,
        'Icon-App-40x40@1x.png': 40,
        'Icon-App-40x40@2x.png': 80,
        'Icon-App-40x40@3x.png': 120,
        'Icon-App-60x60@2x.png': 120,
        'Icon-App-60x60@3x.png': 180,
        'Icon-App-76x76@1x.png': 76,
        'Icon-App-76x76@2x.png': 152,
        'Icon-App-83.5x83.5@2x.png': 167,
        'Icon-App-1024x1024@1x.png': 1024,
    }
    os.makedirs(ios_appicon, exist_ok=True)
    for filename, size in ios_sizes.items():
        icon = create_mininote_icon(size)
        icon.save(os.path.join(ios_appicon, filename), 'PNG')
    print("Generated iOS icons")

if __name__ == '__main__':
    main()
