// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Persian (`fa`).
class AppLocalizationsFa extends AppLocalizations {
  AppLocalizationsFa([String locale = 'fa']) : super(locale);

  @override
  String get addExpense => 'افزودن هزینه';

  @override
  String get amount => 'مبلغ';

  @override
  String get appTitle => 'NimbuStats';

  @override
  String get category => 'دسته‌بندی';

  @override
  String get categoryArchivedBadge => 'بایگانی‌شده';

  @override
  String categoryChildCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count زیر‌دسته',
    );
    return '$_temp0';
  }

  @override
  String get categoryColorLabel => 'رنگ';

  @override
  String categoryDeleted(String name) {
    return '$name حذف شد';
  }

  @override
  String get categoryEditTitle => 'ویرایش دسته‌بندی';

  @override
  String get categoryEmptyAction => 'دسته‌بندی جدید';

  @override
  String get categoryEmptyMessage =>
      'دسته‌بندی‌ها هزینه‌های شما را گروه‌بندی می‌کنند. اولین مورد را بسازید.';

  @override
  String get categoryEmptyTitle => 'دسته‌بندی‌ای وجود ندارد';

  @override
  String get categoryErrorTitle => 'بارگذاری دسته‌بندی‌ها ممکن نشد';

  @override
  String get categoryIconLabel => 'نماد';

  @override
  String get categoryManagerTitle => 'دسته‌بندی‌ها';

  @override
  String get categoryMoveInvalid =>
      'یک دسته‌بندی نمی‌تواند درون خودش قرار گیرد';

  @override
  String get categoryMoveToRoot => 'انتقال به سطح اول';

  @override
  String get categoryNameLabel => 'نام';

  @override
  String get categoryNewTitle => 'دسته‌بندی جدید';

  @override
  String get commonArchive => 'بایگانی';

  @override
  String get commonCancel => 'انصراف';

  @override
  String get commonDelete => 'حذف';

  @override
  String get commonMoveTo => 'انتقال به…';

  @override
  String get commonRename => 'تغییر نام';

  @override
  String get commonRetry => 'تلاش دوباره';

  @override
  String get commonSave => 'ذخیره';

  @override
  String get commonUnarchive => 'خروج از بایگانی';

  @override
  String get commonUndo => 'بازگردانی';

  @override
  String get currency_eur => 'یورو';

  @override
  String get currency_toman => 'تومان';

  @override
  String get currency_try => 'لیر';

  @override
  String get currency_usd => 'دلار';

  @override
  String get seedCategoryEducation => 'آموزش';

  @override
  String get seedCategoryEntertainment => 'سرگرمی';

  @override
  String get seedCategoryFood => 'خوراک و نوشیدنی';

  @override
  String get seedCategoryFoodCoffee => 'کافه';

  @override
  String get seedCategoryFoodDining => 'رستوران';

  @override
  String get seedCategoryFoodGroceries => 'خواربار';

  @override
  String get seedCategoryFreelance => 'کار آزاد';

  @override
  String get seedCategoryGifts => 'هدیه و کمک';

  @override
  String get seedCategoryHealth => 'سلامت';

  @override
  String get seedCategoryHealthDoctor => 'پزشک';

  @override
  String get seedCategoryHealthPharmacy => 'داروخانه';

  @override
  String get seedCategoryHome => 'خانه';

  @override
  String get seedCategoryHomeInternet => 'اینترنت و تلفن';

  @override
  String get seedCategoryHomeRent => 'اجاره';

  @override
  String get seedCategoryHomeUtilities => 'قبض‌ها';

  @override
  String get seedCategoryOther => 'سایر';

  @override
  String get seedCategoryOtherIncome => 'سایر درآمدها';

  @override
  String get seedCategorySalary => 'حقوق';

  @override
  String get seedCategoryShopping => 'خرید';

  @override
  String get seedCategoryShoppingClothing => 'پوشاک';

  @override
  String get seedCategoryShoppingElectronics => 'لوازم الکترونیکی';

  @override
  String get seedCategoryTransport => 'حمل و نقل';

  @override
  String get seedCategoryTransportFuel => 'سوخت';

  @override
  String get seedCategoryTransportPublic => 'حمل و نقل عمومی';

  @override
  String get seedCategoryTransportTaxi => 'تاکسی';

  @override
  String get uncategorized => 'دسته‌بندی‌نشده';
}
