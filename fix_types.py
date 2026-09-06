import sys
import re

f = r'c:\Users\ssbha\Desktop\acccount\26_2_DineMaster\lib\screens\waiter_order_screen.dart'
with open(f, 'r', encoding='utf-8') as file:
    c = file.read()
c = c.replace('_WaiterTableInfo', 'WaiterTableInfo')
c = c.replace('_WaiterCartItem', 'WaiterCartItem')
with open(f, 'w', encoding='utf-8') as file:
    file.write(c)

f2 = r'c:\Users\ssbha\Desktop\acccount\26_2_DineMaster\lib\screens\waiter\components\waiter_cart_panel.dart'
with open(f2, 'r', encoding='utf-8') as file:
    c = file.read()
c = c.replace("import '../../widgets/searchable_dropdown.dart';", "import '../../../widgets/searchable_dropdown.dart';")
c = c.replace("import 'waiter_models.dart';", "import '../waiter_models.dart';")
with open(f2, 'w', encoding='utf-8') as file:
    file.write(c)
print("done")
