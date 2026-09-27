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

  /// No description provided for @analyticsEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Record a few expenses and your spending breakdown appears here.'**
  String get analyticsEmptyBody;

  /// No description provided for @analyticsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing to chart yet'**
  String get analyticsEmptyTitle;

  /// No description provided for @analyticsErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Could not load analytics'**
  String get analyticsErrorTitle;

  /// No description provided for @analyticsOverlapDisclosure.
  ///
  /// In en, this message translates to:
  /// **'These add up to more than the total: a transaction with several tags is counted under each of them.'**
  String get analyticsOverlapDisclosure;

  /// No description provided for @analyticsTabBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Breakdown'**
  String get analyticsTabBreakdown;

  /// No description provided for @analyticsTabCrossTab.
  ///
  /// In en, this message translates to:
  /// **'Tags × categories'**
  String get analyticsTabCrossTab;

  /// No description provided for @analyticsTabDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get analyticsTabDashboard;

  /// No description provided for @analyticsTabPatterns.
  ///
  /// In en, this message translates to:
  /// **'Patterns'**
  String get analyticsTabPatterns;

  /// No description provided for @analyticsTabTrends.
  ///
  /// In en, this message translates to:
  /// **'Trends'**
  String get analyticsTabTrends;

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'NimbuStats'**
  String get appTitle;

  /// No description provided for @breakdownAllCategories.
  ///
  /// In en, this message translates to:
  /// **'All categories'**
  String get breakdownAllCategories;

  /// No description provided for @breakdownConfirmedOnly.
  ///
  /// In en, this message translates to:
  /// **'Confirmed only'**
  String get breakdownConfirmedOnly;

  /// No description provided for @breakdownTransactionCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 transaction} other{{count} transactions}}'**
  String breakdownTransactionCount(int count);

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

  /// No description provided for @crossTabDisclosure.
  ///
  /// In en, this message translates to:
  /// **'A transaction with several tags is counted under each of them, so these cells add up to more than the total. Untagged spending appears in none of them.'**
  String get crossTabDisclosure;

  /// No description provided for @crossTabRowTotal.
  ///
  /// In en, this message translates to:
  /// **'Tag total'**
  String get crossTabRowTotal;

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

  /// No description provided for @dashboardAddStarters.
  ///
  /// In en, this message translates to:
  /// **'Add starter cards'**
  String get dashboardAddStarters;

  /// No description provided for @dashboardCardEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing in this period'**
  String get dashboardCardEmpty;

  /// No description provided for @dashboardCardError.
  ///
  /// In en, this message translates to:
  /// **'This card could not load'**
  String get dashboardCardError;

  /// No description provided for @dashboardEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Pin any chart with its pin button to keep it here, or start with two common ones.'**
  String get dashboardEmptyBody;

  /// No description provided for @dashboardEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing pinned yet'**
  String get dashboardEmptyTitle;

  /// No description provided for @dashboardErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Could not load the dashboard'**
  String get dashboardErrorTitle;

  /// No description provided for @dashboardGoToBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Go to Breakdown'**
  String get dashboardGoToBreakdown;

  /// No description provided for @navAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Analytics'**
  String get navAnalytics;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @onboardingCalendarTitle.
  ///
  /// In en, this message translates to:
  /// **'Calendar'**
  String get onboardingCalendarTitle;

  /// No description provided for @onboardingCurrencyTitle.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get onboardingCurrencyTitle;

  /// No description provided for @onboardingFinish.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get onboardingFinish;

  /// No description provided for @onboardingLocaleTitle.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get onboardingLocaleTitle;

  /// No description provided for @onboardingSeedFailed.
  ///
  /// In en, this message translates to:
  /// **'Setup did not finish'**
  String get onboardingSeedFailed;

  /// No description provided for @onboardingSeeding.
  ///
  /// In en, this message translates to:
  /// **'Setting up…'**
  String get onboardingSeeding;

  /// No description provided for @onboardingSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get onboardingSkip;

  /// No description provided for @onboardingWelcomeBody.
  ///
  /// In en, this message translates to:
  /// **'A few quick choices — or skip and start logging.'**
  String get onboardingWelcomeBody;

  /// No description provided for @onboardingWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to NimbuStats'**
  String get onboardingWelcomeTitle;

  /// No description provided for @patternsDayOfWeek.
  ///
  /// In en, this message translates to:
  /// **'By day of week'**
  String get patternsDayOfWeek;

  /// No description provided for @patternsHourOfDay.
  ///
  /// In en, this message translates to:
  /// **'By hour of day'**
  String get patternsHourOfDay;

  /// No description provided for @patternsReflection.
  ///
  /// In en, this message translates to:
  /// **'Needed against how it felt'**
  String get patternsReflection;

  /// No description provided for @payDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted {name}'**
  String payDeleted(String name);

  /// No description provided for @payEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit payment method'**
  String get payEditTitle;

  /// No description provided for @payEmptyAction.
  ///
  /// In en, this message translates to:
  /// **'New payment method'**
  String get payEmptyAction;

  /// No description provided for @payEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Add cash, a card, or a bank account to see where your money goes out from.'**
  String get payEmptyMessage;

  /// No description provided for @payEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No payment methods'**
  String get payEmptyTitle;

  /// No description provided for @payErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Could not load payment methods'**
  String get payErrorTitle;

  /// No description provided for @payKindBank.
  ///
  /// In en, this message translates to:
  /// **'Bank'**
  String get payKindBank;

  /// No description provided for @payKindCard.
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get payKindCard;

  /// No description provided for @payKindCash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get payKindCash;

  /// No description provided for @payKindLabel.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get payKindLabel;

  /// No description provided for @payKindOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get payKindOther;

  /// No description provided for @payLast4Invalid.
  ///
  /// In en, this message translates to:
  /// **'Enter exactly four digits'**
  String get payLast4Invalid;

  /// No description provided for @payLast4Label.
  ///
  /// In en, this message translates to:
  /// **'Last 4 digits'**
  String get payLast4Label;

  /// No description provided for @payManagerTitle.
  ///
  /// In en, this message translates to:
  /// **'Payment methods'**
  String get payManagerTitle;

  /// No description provided for @payNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get payNameLabel;

  /// No description provided for @payNewTitle.
  ///
  /// In en, this message translates to:
  /// **'New payment method'**
  String get payNewTitle;

  /// No description provided for @payNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get payNone;

  /// No description provided for @periodNextMonth.
  ///
  /// In en, this message translates to:
  /// **'Next month'**
  String get periodNextMonth;

  /// No description provided for @periodPreviousMonth.
  ///
  /// In en, this message translates to:
  /// **'Previous month'**
  String get periodPreviousMonth;

  /// No description provided for @pinNameLastMonths.
  ///
  /// In en, this message translates to:
  /// **'Last {count} months'**
  String pinNameLastMonths(int count);

  /// No description provided for @pinNameSpendingByCategory.
  ///
  /// In en, this message translates to:
  /// **'Spending by category'**
  String get pinNameSpendingByCategory;

  /// No description provided for @pinnedToDashboard.
  ///
  /// In en, this message translates to:
  /// **'Pinned to the dashboard'**
  String get pinnedToDashboard;

  /// No description provided for @pinToDashboard.
  ///
  /// In en, this message translates to:
  /// **'Pin to dashboard'**
  String get pinToDashboard;

  /// No description provided for @reflectionUnset.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get reflectionUnset;

  /// No description provided for @routeNotFoundBody.
  ///
  /// In en, this message translates to:
  /// **'That screen does not exist.'**
  String get routeNotFoundBody;

  /// No description provided for @routeNotFoundGoHome.
  ///
  /// In en, this message translates to:
  /// **'Go to transactions'**
  String get routeNotFoundGoHome;

  /// No description provided for @routeNotFoundTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing here'**
  String get routeNotFoundTitle;

  /// No description provided for @savedViewUnreadable.
  ///
  /// In en, this message translates to:
  /// **'This view can\'t be read'**
  String get savedViewUnreadable;

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

  /// No description provided for @settingsCalendar.
  ///
  /// In en, this message translates to:
  /// **'Calendar'**
  String get settingsCalendar;

  /// No description provided for @settingsCalendarGregorian.
  ///
  /// In en, this message translates to:
  /// **'Gregorian'**
  String get settingsCalendarGregorian;

  /// No description provided for @settingsCalendarJalali.
  ///
  /// In en, this message translates to:
  /// **'Jalali'**
  String get settingsCalendarJalali;

  /// No description provided for @settingsCurrency.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get settingsCurrency;

  /// No description provided for @settingsDebugSeed.
  ///
  /// In en, this message translates to:
  /// **'Seed 5,000 demo transactions'**
  String get settingsDebugSeed;

  /// No description provided for @settingsDebugSeedNoCategories.
  ///
  /// In en, this message translates to:
  /// **'No categories yet, so no demo data was added.'**
  String get settingsDebugSeedNoCategories;

  /// No description provided for @settingsFirstDayOfWeek.
  ///
  /// In en, this message translates to:
  /// **'First day of week'**
  String get settingsFirstDayOfWeek;

  /// No description provided for @settingsLocale.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLocale;

  /// No description provided for @settingsProBadge.
  ///
  /// In en, this message translates to:
  /// **'Pro — free during early access'**
  String get settingsProBadge;

  /// No description provided for @settingsReset.
  ///
  /// In en, this message translates to:
  /// **'Reset settings'**
  String get settingsReset;

  /// No description provided for @settingsSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save that change'**
  String get settingsSaveFailed;

  /// No description provided for @settingsTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsTheme;

  /// No description provided for @settingsThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// No description provided for @settingsThemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsThemeSystem;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @starterThisMonthByCategory.
  ///
  /// In en, this message translates to:
  /// **'This month by category'**
  String get starterThisMonthByCategory;

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

  /// No description provided for @trendsCurrentPeriod.
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get trendsCurrentPeriod;

  /// No description provided for @trendsDeltaNoBaseline.
  ///
  /// In en, this message translates to:
  /// **'No spending to compare'**
  String get trendsDeltaNoBaseline;

  /// No description provided for @trendsPreviousPeriod.
  ///
  /// In en, this message translates to:
  /// **'Last month'**
  String get trendsPreviousPeriod;

  /// No description provided for @txAmountInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid amount'**
  String get txAmountInvalid;

  /// No description provided for @txCategoryMore.
  ///
  /// In en, this message translates to:
  /// **'More…'**
  String get txCategoryMore;

  /// No description provided for @txDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get txDateLabel;

  /// No description provided for @txDaySubtotal.
  ///
  /// In en, this message translates to:
  /// **'Day total'**
  String get txDaySubtotal;

  /// No description provided for @txDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get txDeleted;

  /// No description provided for @txDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Transaction'**
  String get txDetailTitle;

  /// No description provided for @txDirectionExpense.
  ///
  /// In en, this message translates to:
  /// **'Expense'**
  String get txDirectionExpense;

  /// No description provided for @txDirectionIncome.
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get txDirectionIncome;

  /// No description provided for @txEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get txEditTitle;

  /// No description provided for @txFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get txFilterAll;

  /// No description provided for @txFilterDirection.
  ///
  /// In en, this message translates to:
  /// **'Direction'**
  String get txFilterDirection;

  /// No description provided for @txFilterTitle.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get txFilterTitle;

  /// No description provided for @txListEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Log your first expense and it will appear here.'**
  String get txListEmptyMessage;

  /// No description provided for @txListEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No transactions yet'**
  String get txListEmptyTitle;

  /// No description provided for @txListErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Could not load transactions'**
  String get txListErrorTitle;

  /// No description provided for @txListTitle.
  ///
  /// In en, this message translates to:
  /// **'Transactions'**
  String get txListTitle;

  /// No description provided for @txLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get txLoadMore;

  /// No description provided for @txMerchantLabel.
  ///
  /// In en, this message translates to:
  /// **'Merchant'**
  String get txMerchantLabel;

  /// No description provided for @txMonthTotal.
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get txMonthTotal;

  /// No description provided for @txMoreDetails.
  ///
  /// In en, this message translates to:
  /// **'More details'**
  String get txMoreDetails;

  /// No description provided for @txNecessityAvoidable.
  ///
  /// In en, this message translates to:
  /// **'Avoidable'**
  String get txNecessityAvoidable;

  /// No description provided for @txNecessityLabel.
  ///
  /// In en, this message translates to:
  /// **'Was it needed?'**
  String get txNecessityLabel;

  /// No description provided for @txNecessityNeeded.
  ///
  /// In en, this message translates to:
  /// **'Needed'**
  String get txNecessityNeeded;

  /// No description provided for @txNecessityOptional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get txNecessityOptional;

  /// No description provided for @txNoteLabel.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get txNoteLabel;

  /// No description provided for @txPaymentMethodLabel.
  ///
  /// In en, this message translates to:
  /// **'Payment method'**
  String get txPaymentMethodLabel;

  /// No description provided for @txSatisfactionGlad.
  ///
  /// In en, this message translates to:
  /// **'Glad'**
  String get txSatisfactionGlad;

  /// No description provided for @txSatisfactionLabel.
  ///
  /// In en, this message translates to:
  /// **'How do you feel about it?'**
  String get txSatisfactionLabel;

  /// No description provided for @txSatisfactionNeutral.
  ///
  /// In en, this message translates to:
  /// **'Neutral'**
  String get txSatisfactionNeutral;

  /// No description provided for @txSatisfactionRegret.
  ///
  /// In en, this message translates to:
  /// **'Regret'**
  String get txSatisfactionRegret;

  /// No description provided for @txSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get txSaved;

  /// No description provided for @txSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save'**
  String get txSaveFailed;

  /// No description provided for @txSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search merchant or note'**
  String get txSearchHint;

  /// No description provided for @txTagsLabel.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get txTagsLabel;

  /// No description provided for @uncategorized.
  ///
  /// In en, this message translates to:
  /// **'Uncategorized'**
  String get uncategorized;

  /// No description provided for @viewCoversCurrentMonth.
  ///
  /// In en, this message translates to:
  /// **'Shows whichever month the dashboard is on'**
  String get viewCoversCurrentMonth;

  /// No description provided for @viewCoversLastMonths.
  ///
  /// In en, this message translates to:
  /// **'Shows {count} months, ending with the dashboard\'s month'**
  String viewCoversLastMonths(int count);

  /// No description provided for @viewNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get viewNameLabel;

  /// No description provided for @weekdayFriday.
  ///
  /// In en, this message translates to:
  /// **'Fri'**
  String get weekdayFriday;

  /// No description provided for @weekdayMonday.
  ///
  /// In en, this message translates to:
  /// **'Mon'**
  String get weekdayMonday;

  /// No description provided for @weekdaySaturday.
  ///
  /// In en, this message translates to:
  /// **'Sat'**
  String get weekdaySaturday;

  /// No description provided for @weekdaySunday.
  ///
  /// In en, this message translates to:
  /// **'Sun'**
  String get weekdaySunday;

  /// No description provided for @weekdayThursday.
  ///
  /// In en, this message translates to:
  /// **'Thu'**
  String get weekdayThursday;

  /// No description provided for @weekdayTuesday.
  ///
  /// In en, this message translates to:
  /// **'Tue'**
  String get weekdayTuesday;

  /// No description provided for @weekdayWednesday.
  ///
  /// In en, this message translates to:
  /// **'Wed'**
  String get weekdayWednesday;
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
