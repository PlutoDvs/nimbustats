// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get addExpense => 'Add expense';

  @override
  String get amount => 'Amount';

  @override
  String get analyticsEmptyBody =>
      'Record a few expenses and your spending breakdown appears here.';

  @override
  String get analyticsEmptyTitle => 'Nothing to chart yet';

  @override
  String get analyticsErrorTitle => 'Could not load analytics';

  @override
  String get analyticsOverlapDisclosure =>
      'These add up to more than the total: a transaction with several tags is counted under each of them.';

  @override
  String get analyticsTabBreakdown => 'Breakdown';

  @override
  String get analyticsTabCrossTab => 'Tags × categories';

  @override
  String get analyticsTabDashboard => 'Dashboard';

  @override
  String get analyticsTabPatterns => 'Patterns';

  @override
  String get analyticsTabTrends => 'Trends';

  @override
  String get appTitle => 'NimbuStats';

  @override
  String get breakdownAllCategories => 'All categories';

  @override
  String get breakdownConfirmedOnly => 'Confirmed only';

  @override
  String breakdownTransactionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count transactions',
      one: '1 transaction',
    );
    return '$_temp0';
  }

  @override
  String get category => 'Category';

  @override
  String get categoryArchivedBadge => 'Archived';

  @override
  String categoryChildCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count subcategories',
      one: '1 subcategory',
    );
    return '$_temp0';
  }

  @override
  String get categoryColorLabel => 'Colour';

  @override
  String categoryDeleted(String name) {
    return 'Deleted $name';
  }

  @override
  String get categoryEditTitle => 'Edit category';

  @override
  String get categoryEmptyAction => 'New category';

  @override
  String get categoryEmptyMessage =>
      'Categories group your spending. Create your first one.';

  @override
  String get categoryEmptyTitle => 'No categories';

  @override
  String get categoryErrorTitle => 'Could not load categories';

  @override
  String get categoryIconLabel => 'Icon';

  @override
  String get categoryManagerTitle => 'Categories';

  @override
  String get categoryMoveInvalid => 'A category cannot move inside itself';

  @override
  String get categoryMoveToRoot => 'Move to top level';

  @override
  String get categoryNameLabel => 'Name';

  @override
  String get categoryNewTitle => 'New category';

  @override
  String get commonArchive => 'Archive';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonMoveTo => 'Move to…';

  @override
  String get commonRename => 'Rename';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonSave => 'Save';

  @override
  String get commonUnarchive => 'Unarchive';

  @override
  String get commonUndo => 'Undo';

  @override
  String get crossTabDisclosure =>
      'A transaction with several tags is counted under each of them, so these cells add up to more than the total. Untagged spending appears in none of them.';

  @override
  String get crossTabRowTotal => 'Tag total';

  @override
  String get currency_eur => 'EUR';

  @override
  String get currency_toman => 'Toman';

  @override
  String get currency_try => 'TRY';

  @override
  String get currency_usd => 'USD';

  @override
  String get dashboardAddStarters => 'Add starter cards';

  @override
  String get dashboardAvoidableRegretted => 'Avoidable and regretted';

  @override
  String get dashboardCardEmpty => 'Nothing in this period';

  @override
  String get dashboardCardError => 'This card could not load';

  @override
  String get dashboardEmptyBody =>
      'Pin any chart with its pin button to keep it here, or start with two common ones.';

  @override
  String get dashboardEmptyTitle => 'Nothing pinned yet';

  @override
  String get dashboardErrorTitle => 'Could not load the dashboard';

  @override
  String get dashboardGoToBreakdown => 'Go to Breakdown';

  @override
  String get dashboardOverlapNote =>
      'Tags overlap, so cells add up to more than the total.';

  @override
  String get navAnalytics => 'Analytics';

  @override
  String get navHome => 'Home';

  @override
  String get navSettings => 'Settings';

  @override
  String get onboardingCalendarTitle => 'Calendar';

  @override
  String get onboardingCurrencyTitle => 'Currency';

  @override
  String get onboardingFinish => 'Start';

  @override
  String get onboardingLocaleTitle => 'Language';

  @override
  String get onboardingSeedFailed => 'Setup did not finish';

  @override
  String get onboardingSeeding => 'Setting up…';

  @override
  String get onboardingSkip => 'Skip';

  @override
  String get onboardingWelcomeBody =>
      'A few quick choices — or skip and start logging.';

  @override
  String get onboardingWelcomeTitle => 'Welcome to NimbuStats';

  @override
  String get patternsDayOfWeek => 'By day of week';

  @override
  String get patternsHourOfDay => 'By hour of day';

  @override
  String get patternsReflection => 'Needed against how it felt';

  @override
  String payDeleted(String name) {
    return 'Deleted $name';
  }

  @override
  String get payEditTitle => 'Edit payment method';

  @override
  String get payEmptyAction => 'New payment method';

  @override
  String get payEmptyMessage =>
      'Add cash, a card, or a bank account to see where your money goes out from.';

  @override
  String get payEmptyTitle => 'No payment methods';

  @override
  String get payErrorTitle => 'Could not load payment methods';

  @override
  String get payKindBank => 'Bank';

  @override
  String get payKindCard => 'Card';

  @override
  String get payKindCash => 'Cash';

  @override
  String get payKindLabel => 'Type';

  @override
  String get payKindOther => 'Other';

  @override
  String get payLast4Invalid => 'Enter exactly four digits';

  @override
  String get payLast4Label => 'Last 4 digits';

  @override
  String get payManagerTitle => 'Payment methods';

  @override
  String get payNameLabel => 'Name';

  @override
  String get payNewTitle => 'New payment method';

  @override
  String get payNone => 'None';

  @override
  String get periodNextMonth => 'Next month';

  @override
  String get periodPreviousMonth => 'Previous month';

  @override
  String pinNameLastMonths(int count) {
    return 'Last $count months';
  }

  @override
  String get pinNameSpendingByCategory => 'Spending by category';

  @override
  String get pinnedToDashboard => 'Pinned to the dashboard';

  @override
  String get pinToDashboard => 'Pin to dashboard';

  @override
  String get reflectionUnset => 'Not set';

  @override
  String get routeNotFoundBody => 'That screen does not exist.';

  @override
  String get routeNotFoundGoHome => 'Go to transactions';

  @override
  String get routeNotFoundTitle => 'Nothing here';

  @override
  String get savedViewSaveFailed => 'Could not save the change';

  @override
  String get savedViewUnreadable => 'This view can\'t be read';

  @override
  String get seedCategoryEducation => 'Education';

  @override
  String get seedCategoryEntertainment => 'Entertainment';

  @override
  String get seedCategoryFood => 'Food & drink';

  @override
  String get seedCategoryFoodCoffee => 'Coffee';

  @override
  String get seedCategoryFoodDining => 'Dining out';

  @override
  String get seedCategoryFoodGroceries => 'Groceries';

  @override
  String get seedCategoryFreelance => 'Freelance';

  @override
  String get seedCategoryGifts => 'Gifts & charity';

  @override
  String get seedCategoryHealth => 'Health';

  @override
  String get seedCategoryHealthDoctor => 'Doctor';

  @override
  String get seedCategoryHealthPharmacy => 'Pharmacy';

  @override
  String get seedCategoryHome => 'Home';

  @override
  String get seedCategoryHomeInternet => 'Internet & phone';

  @override
  String get seedCategoryHomeRent => 'Rent';

  @override
  String get seedCategoryHomeUtilities => 'Utilities';

  @override
  String get seedCategoryOther => 'Other';

  @override
  String get seedCategoryOtherIncome => 'Other income';

  @override
  String get seedCategorySalary => 'Salary';

  @override
  String get seedCategoryShopping => 'Shopping';

  @override
  String get seedCategoryShoppingClothing => 'Clothing';

  @override
  String get seedCategoryShoppingElectronics => 'Electronics';

  @override
  String get seedCategoryTransport => 'Transport';

  @override
  String get seedCategoryTransportFuel => 'Fuel';

  @override
  String get seedCategoryTransportPublic => 'Public transport';

  @override
  String get seedCategoryTransportTaxi => 'Taxi';

  @override
  String get settingsCalendar => 'Calendar';

  @override
  String get settingsCalendarGregorian => 'Gregorian';

  @override
  String get settingsCalendarJalali => 'Jalali';

  @override
  String get settingsCurrency => 'Currency';

  @override
  String get settingsDebugSeed => 'Seed 5,000 demo transactions';

  @override
  String get settingsDebugSeedNoCategories =>
      'No categories yet, so no demo data was added.';

  @override
  String get settingsFirstDayOfWeek => 'First day of week';

  @override
  String get settingsLocale => 'Language';

  @override
  String get settingsProBadge => 'Pro — free during early access';

  @override
  String get settingsReset => 'Reset settings';

  @override
  String get settingsSaveFailed => 'Could not save that change';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get starterThisMonthByCategory => 'This month by category';

  @override
  String tagCreateInline(String name) {
    return 'Create “$name”';
  }

  @override
  String tagDeleted(String name) {
    return 'Deleted $name';
  }

  @override
  String get tagEditTitle => 'Edit tag';

  @override
  String get tagEmptyAction => 'New tag';

  @override
  String get tagEmptyMessage =>
      'Tags group expenses across categories, like travel or gift.';

  @override
  String get tagEmptyTitle => 'No tags yet';

  @override
  String get tagErrorTitle => 'Could not load tags';

  @override
  String get tagManagerTitle => 'Tags';

  @override
  String tagMoreCount(int count) {
    return '+$count';
  }

  @override
  String get tagNameLabel => 'Name';

  @override
  String get tagNewTitle => 'New tag';

  @override
  String get tagPickerSearchHint => 'Search or create';

  @override
  String get tagPickerTitle => 'Tags';

  @override
  String tagUsageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count uses',
      one: '1 use',
    );
    return '$_temp0';
  }

  @override
  String get trendsCurrentPeriod => 'This month';

  @override
  String get trendsDeltaNoBaseline => 'No spending to compare';

  @override
  String get trendsPreviousPeriod => 'Last month';

  @override
  String get txAmountInvalid => 'Enter a valid amount';

  @override
  String get txCategoryMore => 'More…';

  @override
  String get txDateLabel => 'Date';

  @override
  String get txDaySubtotal => 'Day total';

  @override
  String get txDeleted => 'Deleted';

  @override
  String get txDetailTitle => 'Transaction';

  @override
  String get txDirectionExpense => 'Expense';

  @override
  String get txDirectionIncome => 'Income';

  @override
  String get txEditTitle => 'Edit';

  @override
  String get txFilterAll => 'All';

  @override
  String get txFilterDirection => 'Direction';

  @override
  String get txFilterTitle => 'Filters';

  @override
  String get txListEmptyMessage =>
      'Log your first expense and it will appear here.';

  @override
  String get txListEmptyTitle => 'No transactions yet';

  @override
  String get txListErrorTitle => 'Could not load transactions';

  @override
  String get txListTitle => 'Transactions';

  @override
  String get txLoadMore => 'Load more';

  @override
  String get txMerchantLabel => 'Merchant';

  @override
  String get txMonthTotal => 'This month';

  @override
  String get txMoreDetails => 'More details';

  @override
  String get txNecessityAvoidable => 'Avoidable';

  @override
  String get txNecessityLabel => 'Was it needed?';

  @override
  String get txNecessityNeeded => 'Needed';

  @override
  String get txNecessityOptional => 'Optional';

  @override
  String get txNoteLabel => 'Note';

  @override
  String get txPaymentMethodLabel => 'Payment method';

  @override
  String get txSatisfactionGlad => 'Glad';

  @override
  String get txSatisfactionLabel => 'How do you feel about it?';

  @override
  String get txSatisfactionNeutral => 'Neutral';

  @override
  String get txSatisfactionRegret => 'Regret';

  @override
  String get txSaved => 'Saved';

  @override
  String get txSaveFailed => 'Could not save';

  @override
  String get txSearchHint => 'Search merchant or note';

  @override
  String get txTagsLabel => 'Tags';

  @override
  String get uncategorized => 'Uncategorized';

  @override
  String get viewCoversCurrentMonth =>
      'Shows whichever month the dashboard is on';

  @override
  String viewCoversLastMonths(int count) {
    return 'Shows $count months, ending with the dashboard\'s month';
  }

  @override
  String get viewNameLabel => 'Name';

  @override
  String get weekdayFriday => 'Fri';

  @override
  String get weekdayMonday => 'Mon';

  @override
  String get weekdaySaturday => 'Sat';

  @override
  String get weekdaySunday => 'Sun';

  @override
  String get weekdayThursday => 'Thu';

  @override
  String get weekdayTuesday => 'Tue';

  @override
  String get weekdayWednesday => 'Wed';
}
