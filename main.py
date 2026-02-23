import sys
from PyQt6.QtWidgets import QApplication, QMessageBox
from views import MainWindow, LoginDialog, ThemeManager
from utils import setup_logging, logger
from services import UserService

logger = setup_logging()


def _ensure_default_admin():
    """Create a default Admin account if no users exist in the DB."""
    svc = UserService()
    users = svc.get_all_users()
    if not users:
        logger.info("No users found — creating default admin account")
        svc.create_user(
            username="admin",
            password="admin1234",
            role="Admin",
            full_name="ผู้ดูแลระบบ"
        )
        logger.info("Default admin created: username=admin, password=admin1234")


def main():
    logger.info("Starting Maintenance Super App v3.3")
    app = QApplication(sys.argv)
    app.setStyle("Fusion")
    ThemeManager.set_app(app)
    ThemeManager._apply_globals()          # sync module globals to default theme
    app.setStyleSheet(ThemeManager.qss())  # apply theme QSS to application


    # Seed default admin if DB is empty
    _ensure_default_admin()

    # Show login dialog
    login = LoginDialog()
    login.setStyleSheet(login.styleSheet())
    if not login.exec() or not login.authenticated_user:
        # User closed login window without logging in
        sys.exit(0)

    user = login.authenticated_user
    logger.info(f"Login success: {user.username} [{user.role}]")

    window = MainWindow(user=user)
    window.show()

    sys.exit(app.exec())


if __name__ == "__main__":
    main()
