import 'package:flutter/widgets.dart';

/// Material 的展开宽度配合非紧凑高度，适用于并排显示工作区内容。
bool supportsTwoPanes(Size window) =>
    window.width >= 840 && window.height >= 480;
