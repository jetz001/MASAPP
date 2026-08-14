import 'package:bcrypt/bcrypt.dart';

void main() {
  final hash = r'$2a$10$rldt6VRimShGDHOZY8HVEOwUl/1Cg8DfsDA5jZ3DcsqtWtf5bm7p2';
  for (int i = 0; i < 10000; i++) {
    final pin = i.toString().padLeft(4, '0');
    if (BCrypt.checkpw(pin, hash)) {
      print('PIN is $pin');
      break;
    }
  }
}
