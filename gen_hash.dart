import 'package:bcrypt/bcrypt.dart';

void main() {
  print(BCrypt.hashpw('1234', BCrypt.gensalt()));
}
