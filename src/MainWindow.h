#pragma once

#include <QMainWindow>

class QPushButton;

class MainWindow : public QMainWindow {
    Q_OBJECT
public:
    explicit MainWindow(QWidget* parent = nullptr);

private slots:
    void onAccessibilityClicked();
    void onScreenRecordingClicked();

private:
    QRect screenRectFor(QWidget* widget) const;

    QPushButton* accessibilityButton_;
    QPushButton* screenRecordingButton_;
};
