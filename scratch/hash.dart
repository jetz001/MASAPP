import 'package:bcrypt/bcrypt.dart'; void main() { print(BCrypt.hashpw('Admin@1234', BCrypt.gensalt())); }
