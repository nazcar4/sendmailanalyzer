use strict; use warnings; use ExtUtils::MakeMaker;
WriteMakefile(
 NAME=>'SendmailAnalyzer::V10', VERSION_FROM=>'lib/SendmailAnalyzer/V10.pm',
 AUTHOR=>'Nazcar <nazcar@almogavers.net>',
 ABSTRACT=>'Modern Postfix-first mail log analyzer and web dashboard',
 LICENSE=>'gpl_3',
 PREREQ_PM=>{'JSON::PP'=>0,'URI::Escape'=>0,'DBI'=>0,'DBD::SQLite'=>0,'Plack'=>0,'Digest::SHA'=>0,'IO::Uncompress::Gunzip'=>0,'Test::More'=>0},
 EXE_FILES=>[qw(bin/sa10_parse bin/sa10_collect bin/sa10_coverage bin/sa10_import_legacy bin/sa10_db bin/sa10_selftest bin/sa10_reconcile bin/sa10_migration_check bin/sa10_migrate bin/sa10_migration_audit bin/sa10_rspamd_audit bin/sa10_web bin/sa10_apache_upgrade bin/sa10_retire_94)],
);
