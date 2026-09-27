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
  String get analyticsEmptyBody =>
      'چند هزینه ثبت کنید تا تفکیک خرج‌هایتان اینجا نمایش داده شود.';

  @override
  String get analyticsEmptyTitle => 'هنوز چیزی برای نمودار نیست';

  @override
  String get analyticsErrorTitle => 'تحلیل‌ها بارگذاری نشد';

  @override
  String get analyticsOverlapDisclosure =>
      'جمع این‌ها از کل بیشتر است: تراکنشی که چند برچسب دارد زیر هر کدام شمرده می‌شود.';

  @override
  String get analyticsTabBreakdown => 'تفکیک';

  @override
  String get analyticsTabCrossTab => 'برچسب × دسته';

  @override
  String get analyticsTabDashboard => 'داشبورد';

  @override
  String get analyticsTabPatterns => 'الگوها';

  @override
  String get analyticsTabTrends => 'روند';

  @override
  String get appTitle => 'NimbuStats';

  @override
  String get breakdownAllCategories => 'همه دسته‌ها';

  @override
  String get breakdownConfirmedOnly => 'فقط تأییدشده';

  @override
  String breakdownTransactionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count تراکنش',
    );
    return '$_temp0';
  }

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
  String get crossTabDisclosure =>
      'تراکنشی که چند برچسب دارد زیر هر کدام شمرده می‌شود، پس جمع این خانه‌ها از کل بیشتر است. خرج بدون برچسب در هیچ‌کدام نمی‌آید.';

  @override
  String get crossTabRowTotal => 'جمع برچسب';

  @override
  String get currency_eur => 'یورو';

  @override
  String get currency_toman => 'تومان';

  @override
  String get currency_try => 'لیر';

  @override
  String get currency_usd => 'دلار';

  @override
  String get dashboardAddStarters => 'افزودن کارت‌های آغازین';

  @override
  String get dashboardAvoidableRegretted => 'قابل اجتناب و پشیمان';

  @override
  String get dashboardCardEmpty => 'در این بازه چیزی نیست';

  @override
  String get dashboardCardError => 'این کارت بارگیری نشد';

  @override
  String get dashboardEmptyBody =>
      'هر نموداری را با دکمهٔ سنجاقش اینجا نگه دارید، یا با دو نمودار رایج شروع کنید.';

  @override
  String get dashboardEmptyTitle => 'هنوز چیزی سنجاق نشده';

  @override
  String get dashboardErrorTitle => 'داشبورد بارگیری نشد';

  @override
  String get dashboardGoToBreakdown => 'رفتن به تفکیک';

  @override
  String get dashboardOverlapNote =>
      'برچسب‌ها هم‌پوشانی دارند؛ جمع خانه‌ها از کل بیشتر است.';

  @override
  String get navAnalytics => 'تحلیل‌ها';

  @override
  String get navHome => 'خانه';

  @override
  String get navSettings => 'تنظیمات';

  @override
  String get onboardingCalendarTitle => 'تقویم';

  @override
  String get onboardingCurrencyTitle => 'واحد پول';

  @override
  String get onboardingFinish => 'شروع';

  @override
  String get onboardingLocaleTitle => 'زبان';

  @override
  String get onboardingSeedFailed => 'آماده‌سازی کامل نشد';

  @override
  String get onboardingSeeding => 'در حال آماده‌سازی…';

  @override
  String get onboardingSkip => 'رد کردن';

  @override
  String get onboardingWelcomeBody =>
      'چند انتخاب کوتاه — یا رد کنید و شروع کنید.';

  @override
  String get onboardingWelcomeTitle => 'به نیمبوستتس خوش آمدید';

  @override
  String get patternsDayOfWeek => 'بر اساس روز هفته';

  @override
  String get patternsHourOfDay => 'بر اساس ساعت روز';

  @override
  String get patternsReflection => 'نیاز در برابر حس';

  @override
  String payDeleted(String name) {
    return '$name حذف شد';
  }

  @override
  String get payEditTitle => 'ویرایش روش پرداخت';

  @override
  String get payEmptyAction => 'روش پرداخت جدید';

  @override
  String get payEmptyMessage =>
      'نقدی، کارت یا حساب بانکی اضافه کنید تا ببینید پول از کجا خارج می‌شود.';

  @override
  String get payEmptyTitle => 'روش پرداختی ثبت نشده';

  @override
  String get payErrorTitle => 'بارگذاری روش‌های پرداخت ممکن نشد';

  @override
  String get payKindBank => 'بانک';

  @override
  String get payKindCard => 'کارت';

  @override
  String get payKindCash => 'نقدی';

  @override
  String get payKindLabel => 'نوع';

  @override
  String get payKindOther => 'سایر';

  @override
  String get payLast4Invalid => 'دقیقاً چهار رقم وارد کنید';

  @override
  String get payLast4Label => 'چهار رقم آخر';

  @override
  String get payManagerTitle => 'روش‌های پرداخت';

  @override
  String get payNameLabel => 'نام';

  @override
  String get payNewTitle => 'روش پرداخت جدید';

  @override
  String get payNone => 'هیچ‌کدام';

  @override
  String get periodNextMonth => 'ماه بعد';

  @override
  String get periodPreviousMonth => 'ماه قبل';

  @override
  String pinNameLastMonths(int count) {
    return '$count ماه اخیر';
  }

  @override
  String get pinNameSpendingByCategory => 'هزینه‌ها به تفکیک دسته';

  @override
  String get pinnedToDashboard => 'به داشبورد سنجاق شد';

  @override
  String get pinToDashboard => 'سنجاق به داشبورد';

  @override
  String get reflectionUnset => 'ثبت‌نشده';

  @override
  String get routeNotFoundBody => 'چنین صفحه‌ای وجود ندارد.';

  @override
  String get routeNotFoundGoHome => 'رفتن به تراکنش‌ها';

  @override
  String get routeNotFoundTitle => 'چیزی اینجا نیست';

  @override
  String get savedViewSaveFailed => 'تغییر ذخیره نشد';

  @override
  String get savedViewUnreadable => 'این نما خوانا نیست';

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
  String get settingsCalendar => 'تقویم';

  @override
  String get settingsCalendarGregorian => 'میلادی';

  @override
  String get settingsCalendarJalali => 'شمسی';

  @override
  String get settingsCurrency => 'واحد پول';

  @override
  String get settingsDebugSeed => 'ساخت ۵۰۰۰ تراکنش نمونه';

  @override
  String get settingsDebugSeedNoCategories =>
      'هنوز دسته‌بندی‌ای نیست، پس داده‌ی نمونه اضافه نشد.';

  @override
  String get settingsFirstDayOfWeek => 'اولین روز هفته';

  @override
  String get settingsLocale => 'زبان';

  @override
  String get settingsProBadge => 'حرفه‌ای — رایگان در دسترسی زودهنگام';

  @override
  String get settingsReset => 'بازنشانی تنظیمات';

  @override
  String get settingsSaveFailed => 'این تغییر ذخیره نشد';

  @override
  String get settingsTheme => 'پوسته';

  @override
  String get settingsThemeDark => 'تیره';

  @override
  String get settingsThemeLight => 'روشن';

  @override
  String get settingsThemeSystem => 'سیستم';

  @override
  String get settingsTitle => 'تنظیمات';

  @override
  String get starterThisMonthByCategory => 'این ماه به تفکیک دسته';

  @override
  String tagCreateInline(String name) {
    return 'ساخت «$name»';
  }

  @override
  String tagDeleted(String name) {
    return '$name حذف شد';
  }

  @override
  String get tagEditTitle => 'ویرایش برچسب';

  @override
  String get tagEmptyAction => 'برچسب جدید';

  @override
  String get tagEmptyMessage =>
      'برچسب‌ها هزینه‌ها را فراتر از دسته‌بندی گروه‌بندی می‌کنند، مثل سفر یا هدیه.';

  @override
  String get tagEmptyTitle => 'هنوز برچسبی ندارید';

  @override
  String get tagErrorTitle => 'بارگذاری برچسب‌ها ممکن نشد';

  @override
  String get tagManagerTitle => 'برچسب‌ها';

  @override
  String tagMoreCount(int count) {
    return '+$count';
  }

  @override
  String get tagNameLabel => 'نام';

  @override
  String get tagNewTitle => 'برچسب جدید';

  @override
  String get tagPickerSearchHint => 'جست‌وجو یا ساخت';

  @override
  String get tagPickerTitle => 'برچسب‌ها';

  @override
  String tagUsageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count بار استفاده',
    );
    return '$_temp0';
  }

  @override
  String get trendsCurrentPeriod => 'این ماه';

  @override
  String get trendsDeltaNoBaseline => 'چیزی برای مقایسه نیست';

  @override
  String get trendsPreviousPeriod => 'ماه گذشته';

  @override
  String get txAmountInvalid => 'مبلغ معتبر وارد کنید';

  @override
  String get txCategoryMore => 'بیشتر…';

  @override
  String get txDateLabel => 'تاریخ';

  @override
  String get txDaySubtotal => 'مجموع روز';

  @override
  String get txDeleted => 'حذف شد';

  @override
  String get txDetailTitle => 'تراکنش';

  @override
  String get txDirectionExpense => 'هزینه';

  @override
  String get txDirectionIncome => 'درآمد';

  @override
  String get txEditTitle => 'ویرایش';

  @override
  String get txFilterAll => 'همه';

  @override
  String get txFilterDirection => 'نوع';

  @override
  String get txFilterTitle => 'فیلترها';

  @override
  String get txListEmptyMessage =>
      'اولین هزینه‌تان را ثبت کنید تا اینجا نمایش داده شود.';

  @override
  String get txListEmptyTitle => 'هنوز تراکنشی ثبت نشده';

  @override
  String get txListErrorTitle => 'بارگذاری تراکنش‌ها ممکن نشد';

  @override
  String get txListTitle => 'تراکنش‌ها';

  @override
  String get txLoadMore => 'بارگذاری بیشتر';

  @override
  String get txMerchantLabel => 'فروشنده';

  @override
  String get txMonthTotal => 'این ماه';

  @override
  String get txMoreDetails => 'جزئیات بیشتر';

  @override
  String get txNecessityAvoidable => 'قابل اجتناب';

  @override
  String get txNecessityLabel => 'لازم بود؟';

  @override
  String get txNecessityNeeded => 'لازم';

  @override
  String get txNecessityOptional => 'اختیاری';

  @override
  String get txNoteLabel => 'یادداشت';

  @override
  String get txPaymentMethodLabel => 'روش پرداخت';

  @override
  String get txSatisfactionGlad => 'راضی';

  @override
  String get txSatisfactionLabel => 'چه حسی درباره‌اش دارید؟';

  @override
  String get txSatisfactionNeutral => 'خنثی';

  @override
  String get txSatisfactionRegret => 'پشیمان';

  @override
  String get txSaved => 'ذخیره شد';

  @override
  String get txSaveFailed => 'ذخیره نشد';

  @override
  String get txSearchHint => 'جست‌وجوی فروشنده یا یادداشت';

  @override
  String get txTagsLabel => 'برچسب‌ها';

  @override
  String get uncategorized => 'دسته‌بندی‌نشده';

  @override
  String get viewCoversCurrentMonth =>
      'همان ماهی را نشان می‌دهد که داشبورد روی آن است';

  @override
  String viewCoversLastMonths(int count) {
    return '$count ماه را تا ماهِ داشبورد نشان می‌دهد';
  }

  @override
  String get viewNameLabel => 'نام';

  @override
  String get weekdayFriday => 'جمعه';

  @override
  String get weekdayMonday => 'دوشنبه';

  @override
  String get weekdaySaturday => 'شنبه';

  @override
  String get weekdaySunday => 'یکشنبه';

  @override
  String get weekdayThursday => 'پنجشنبه';

  @override
  String get weekdayTuesday => 'سه‌شنبه';

  @override
  String get weekdayWednesday => 'چهارشنبه';
}
