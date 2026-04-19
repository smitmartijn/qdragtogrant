#include <QApplication>

#include "MainWindow.h"

int main(int argc, char** argv) {
    QApplication app(argc, argv);
    app.setApplicationName("QDragToGrant Sample");
    app.setOrganizationDomain("lostdomain.org");

    MainWindow window;
    window.resize(760, 420);
    window.setMinimumSize(620, 320);
    window.show();

    return app.exec();
}
