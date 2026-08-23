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
  String get appTitle => 'NimbuStats';

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
  String get currency_eur => 'EUR';

  @override
  String get currency_toman => 'Toman';

  @override
  String get currency_try => 'TRY';

  @override
  String get currency_usd => 'USD';

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
  String get txAmountInvalid => 'Enter a valid amount';

  @override
  String get txCategoryMore => 'More…';

  @override
  String get txDateLabel => 'Date';

  @override
  String get txDirectionExpense => 'Expense';

  @override
  String get txDirectionIncome => 'Income';

  @override
  String get txMerchantLabel => 'Merchant';

  @override
  String get txMoreDetails => 'More details';

  @override
  String get txNoteLabel => 'Note';

  @override
  String get txPaymentMethodLabel => 'Payment method';

  @override
  String get txSaveFailed => 'Could not save';

  @override
  String get txSaved => 'Saved';

  @override
  String get txTagsLabel => 'Tags';

  @override
  String get uncategorized => 'Uncategorized';
}
