import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fa.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fa'),
  ];

  /// No description provided for @addExpense.
  ///
  /// In en, this message translates to:
  /// **'Add expense'**
  String get addExpense;

  /// No description provided for @amount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get amount;

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'NimbuStats'**
  String get appTitle;

  /// No description provided for @category.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get category;

  /// No description provided for @categoryArchivedBadge.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get categoryArchivedBadge;

  /// No description provided for @categoryChildCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 subcategory} other{{count} subcategories}}'**
  String categoryChildCount(int count);

  /// No description provided for @categoryColorLabel.
  ///
  /// In en, this message translates to:
  /// **'Colour'**
  String get categoryColorLabel;

  /// No description provided for @categoryDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted {name}'**
  String categoryDeleted(String name);

  /// No description provided for @categoryEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit category'**
  String get categoryEditTitle;

  /// No description provided for @categoryEmptyAction.
  ///
  /// In en, this message translates to:
  /// **'New category'**
  String get categoryEmptyAction;

  /// No description provided for @categoryEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Categories group your spending. Create your first one.'**
  String get categoryEmptyMessage;

  /// No description provided for @categoryEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No categories'**
  String get categoryEmptyTitle;

  /// No description provided for @categoryErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Could not load categories'**
  String get categoryErrorTitle;

  /// No description provided for @categoryIconLabel.
  ///
  /// In en, this message translates to:
  /// **'Icon'**
  String get categoryIconLabel;

  /// No description provided for @categoryManagerTitle.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get categoryManagerTitle;

  /// No description provided for @categoryMoveInvalid.
  ///
  /// In en, this message translates to:
  /// **'A category cannot move inside itself'**
  String get categoryMoveInvalid;

  /// No description provided for @categoryMoveToRoot.
  ///
  /// In en, this message translates to:
  /// **'Move to top level'**
  String get categoryMoveToRoot;

  /// No description provided for @categoryNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get categoryNameLabel;

  /// No description provided for @categoryNewTitle.
  ///
  /// In en, this message translates to:
  /// **'New category'**
  String get categoryNewTitle;

  /// No description provided for @commonArchive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get commonArchive;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @commonMoveTo.
  ///
  /// In en, this message translates to:
  /// **'Move to…'**
  String get commonMoveTo;

  /// No description provided for @commonRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get commonRename;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonUnarchive.
  ///
  /// In en, this message translates to:
  /// **'Unarchive'**
  String get commonUnarchive;

  /// No description provided for @commonUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get commonUndo;

  /// No description provided for @currency_eur.
  ///
  /// In en, this message translates to:
  /// **'EUR'**
  String get currency_eur;

  /// No description provided for @currency_toman.
  ///
  /// In en, this message translates to:
  /// **'Toman'**
  String get currency_toman;

  /// No description provided for @currency_try.
  ///
  /// In en, this message translates to:
  /// **'TRY'**
  String get currency_try;

  /// No description provided for @currency_usd.
  ///
  /// In en, this message translates to:
  /// **'USD'**
  String get currency_usd;

  /// No description provided for @seedCategoryEducation.
  ///
  /// In en, this message translates to:
  /// **'Education'**
  String get seedCategoryEducation;

  /// No description provided for @seedCategoryEntertainment.
  ///
  /// In en, this message translates to:
  /// **'Entertainment'**
  String get seedCategoryEntertainment;

  /// No description provided for @seedCategoryFood.
  ///
  /// In en, this message translates to:
  /// **'Food & drink'**
  String get seedCategoryFood;

  /// No description provided for @seedCategoryFoodCoffee.
  ///
  /// In en, this message translates to:
  /// **'Coffee'**
  String get seedCategoryFoodCoffee;

  /// No description provided for @seedCategoryFoodDining.
  ///
  /// In en, this message translates to:
  /// **'Dining out'**
  String get seedCategoryFoodDining;

  /// No description provided for @seedCategoryFoodGroceries.
  ///
  /// In en, this message translates to:
  /// **'Groceries'**
  String get seedCategoryFoodGroceries;

  /// No description provided for @seedCategoryFreelance.
  ///
  /// In en, this message translates to:
  /// **'Freelance'**
  String get seedCategoryFreelance;

  /// No description provided for @seedCategoryGifts.
  ///
  /// In en, this message translates to:
  /// **'Gifts & charity'**
  String get seedCategoryGifts;

  /// No description provided for @seedCategoryHealth.
  ///
  /// In en, this message translates to:
  /// **'Health'**
  String get seedCategoryHealth;

  /// No description provided for @seedCategoryHealthDoctor.
  ///
  /// In en, this message translates to:
  /// **'Doctor'**
  String get seedCategoryHealthDoctor;

  /// No description provided for @seedCategoryHealthPharmacy.
  ///
  /// In en, this message translates to:
  /// **'Pharmacy'**
  String get seedCategoryHealthPharmacy;

  /// No description provided for @seedCategoryHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get seedCategoryHome;

  /// No description provided for @seedCategoryHomeInternet.
  ///
  /// In en, this message translates to:
  /// **'Internet & phone'**
  String get seedCategoryHomeInternet;

  /// No description provided for @seedCategoryHomeRent.
  ///
  /// In en, this message translates to:
  /// **'Rent'**
  String get seedCategoryHomeRent;

  /// No description provided for @seedCategoryHomeUtilities.
  ///
  /// In en, this message translates to:
  /// **'Utilities'**
  String get seedCategoryHomeUtilities;

  /// No description provided for @seedCategoryOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get seedCategoryOther;

  /// No description provided for @seedCategoryOtherIncome.
  ///
  /// In en, this message translates to:
  /// **'Other income'**
  String get seedCategoryOtherIncome;

  /// No description provided for @seedCategorySalary.
  ///
  /// In en, this message translates to:
  /// **'Salary'**
  String get seedCategorySalary;

  /// No description provided for @seedCategoryShopping.
  ///
  /// In en, this message translates to:
  /// **'Shopping'**
  String get seedCategoryShopping;

  /// No description provided for @seedCategoryShoppingClothing.
  ///
  /// In en, this message translates to:
  /// **'Clothing'**
  String get seedCategoryShoppingClothing;

  /// No description provided for @seedCategoryShoppingElectronics.
  ///
  /// In en, this message translates to:
  /// **'Electronics'**
  String get seedCategoryShoppingElectronics;

  /// No description provided for @seedCategoryTransport.
  ///
  /// In en, this message translates to:
  /// **'Transport'**
  String get seedCategoryTransport;

  /// No description provided for @seedCategoryTransportFuel.
  ///
  /// In en, this message translates to:
  /// **'Fuel'**
  String get seedCategoryTransportFuel;

  /// No description provided for @seedCategoryTransportPublic.
  ///
  /// In en, this message translates to:
  /// **'Public transport'**
  String get seedCategoryTransportPublic;

  /// No description provided for @seedCategoryTransportTaxi.
  ///
  /// In en, this message translates to:
  /// **'Taxi'**
  String get seedCategoryTransportTaxi;

  /// No description provided for @tagCreateInline.
  ///
  /// In en, this message translates to:
  /// **'Create “{name}”'**
  String tagCreateInline(String name);

  /// No description provided for @tagDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted {name}'**
  String tagDeleted(String name);

  /// No description provided for @tagEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit tag'**
  String get tagEditTitle;

  /// No description provided for @tagEmptyAction.
  ///
  /// In en, this message translates to:
  /// **'New tag'**
  String get tagEmptyAction;

  /// No description provided for @tagEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Tags group expenses across categories, like travel or gift.'**
  String get tagEmptyMessage;

  /// No description provided for @tagEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No tags yet'**
  String get tagEmptyTitle;

  /// No description provided for @tagErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Could not load tags'**
  String get tagErrorTitle;

  /// No description provided for @tagManagerTitle.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get tagManagerTitle;

  /// No description provided for @tagMoreCount.
  ///
  /// In en, this message translates to:
  /// **'+{count}'**
  String tagMoreCount(int count);

  /// No description provided for @tagNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get tagNameLabel;

  /// No description provided for @tagNewTitle.
  ///
  /// In en, this message translates to:
  /// **'New tag'**
  String get tagNewTitle;

  /// No description provided for @tagPickerSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search or create'**
  String get tagPickerSearchHint;

  /// No description provided for @tagPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get tagPickerTitle;

  /// No description provided for @tagUsageCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 use} other{{count} uses}}'**
  String tagUsageCount(int count);

  /// No description provided for @uncategorized.
  ///
  /// In en, this message translates to:
  /// **'Uncategorized'**
  String get uncategorized;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fa'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fa':
      return AppLocalizationsFa();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
