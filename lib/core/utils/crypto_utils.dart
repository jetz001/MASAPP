import 'package:bcrypt/bcrypt.dart';

class CryptoUtils {
  /// Hash a password using bcrypt
  static String hashPassword(String password) {
    return BCrypt.hashpw(password, BCrypt.gensalt());
  }

  /// Verify a password against a hash
  static bool verifyPassword(String password, String hashed) {
    try {
      return BCrypt.checkpw(password, hashed);
    } catch (e) {
      // Fallback for plain text transition if needed
      return password == hashed;
    }
  }
}
