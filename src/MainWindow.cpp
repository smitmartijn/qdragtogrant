#include "MainWindow.h"

#include <QHBoxLayout>
#include <QLabel>
#include <QPushButton>
#include <QVBoxLayout>
#include <QWidget>

#include "qdragtogrant/QDragToGrant.h"

MainWindow::MainWindow(QWidget* parent) : QMainWindow(parent) {
    auto* central = new QWidget(this);
    setCentralWidget(central);

    auto* layout = new QVBoxLayout(central);
    layout->setContentsMargins(32, 32, 32, 32);
    layout->setSpacing(24);
    layout->setAlignment(Qt::AlignTop | Qt::AlignLeft);

    auto* heading = new QLabel(tr("QDragToGrant Sample"), central);
    heading->setStyleSheet("font-size: 13px; font-weight: 600; color: gray;");
    layout->addWidget(heading);

    auto* sub = new QLabel(
        tr("Open System Settings and launch the drag helper from the control you want to test."),
        central);
    sub->setWordWrap(true);
    sub->setStyleSheet("font-size: 15px; color: gray;");
    sub->setMaximumWidth(520);
    layout->addWidget(sub);

    auto* row = new QHBoxLayout();
    row->setSpacing(12);

    accessibilityButton_ = new QPushButton(tr("Accessibility"), central);
    accessibilityButton_->setMinimumHeight(36);
    accessibilityButton_->setDefault(true);
    connect(accessibilityButton_, &QPushButton::clicked,
            this, &MainWindow::onAccessibilityClicked);
    row->addWidget(accessibilityButton_);

    screenRecordingButton_ = new QPushButton(tr("Screen Recording"), central);
    screenRecordingButton_->setMinimumHeight(36);
    connect(screenRecordingButton_, &QPushButton::clicked,
            this, &MainWindow::onScreenRecordingClicked);
    row->addWidget(screenRecordingButton_);

    row->addStretch();
    layout->addLayout(row);
    layout->addStretch();

    setWindowTitle(tr("QDragToGrant Sample"));
}

QRect MainWindow::screenRectFor(QWidget* widget) const {
    QPoint topLeft = widget->mapToGlobal(QPoint(0, 0));
    return QRect(topLeft, widget->size());
}

void MainWindow::onAccessibilityClicked() {
    QDragToGrant::Assistant::shared().present(QDragToGrant::Panel::Accessibility,
                                         screenRectFor(accessibilityButton_));
}

void MainWindow::onScreenRecordingClicked() {
    QDragToGrant::Assistant::shared().present(QDragToGrant::Panel::ScreenRecording,
                                         screenRectFor(screenRecordingButton_));
}
