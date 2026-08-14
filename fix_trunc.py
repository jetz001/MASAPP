import os

p = r'lib\features\work_orders\work_order_detail_screen.dart'
with open(p, 'rb') as f:
    data = f.read()

# find the bad class
idx = data.rfind(b'class _WorkOrderPartsCard')
if idx != -1:
    good_data = data[:idx]
    with open(p, 'wb') as f:
        f.write(good_data)
    print('Truncated bad part')
else:
    print('Not found in bytes')
    # Maybe powershell wrote UTF-16?
    idx2 = data.rfind("class _WorkOrderPartsCard".encode('utf-16le'))
    if idx2 != -1:
        good_data = data[:idx2]
        with open(p, 'wb') as f:
            f.write(good_data)
        print('Truncated bad part (utf-16)')
    else:
        # Check ANSI
        idx3 = data.rfind("class _WorkOrderPartsCard".encode('windows-1252'))
        if idx3 != -1:
            good_data = data[:idx3]
            with open(p, 'wb') as f:
                f.write(good_data)
            print('Truncated bad part (windows-1252)')
