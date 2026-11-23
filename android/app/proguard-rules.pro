# Room 通过反射创建 WorkManager 数据库，R8 完整模式需显式保留无参构造器。
-keepclassmembers class androidx.work.impl.WorkDatabase_Impl {
    <init>();
}
