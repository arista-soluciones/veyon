/*
 * MacCoreFunctions.cpp - implementation of MacCoreFunctions class
 *
 * Copyright (c) 2026 Veyon macOS port contributors
 *
 * This file is part of Veyon - https://veyon.io
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public
 * License along with this program (see COPYING); if not, write to the
 * Free Software Foundation, Inc., 59 Temple Place - Suite 330,
 * Boston, MA 02111-1307, USA.
 *
 */

#include <QProcess>
#include <QScreen>
#include <QSocketNotifier>
#include <QTextStream>
#include <QWidget>

#include <cstdlib>
#include <grp.h>
#include <libproc.h>
#include <pwd.h>
#include <unistd.h>
#include <sys/param.h>

#include <IOKit/pwr_mgt/IOPMLib.h>

#include "MacCoreFunctions.h"
#include "StandardInputReader.h"


bool MacCoreFunctions::applyConfiguration()
{
	return true;
}



bool MacCoreFunctions::prepareSessionBusAccess()
{
	// there's no session bus on macOS
	return true;
}



void MacCoreFunctions::initNativeLoggingSystem( const QString& appName )
{
	m_logHandle = os_log_create( "io.veyon.Veyon", appName.toUtf8().constData() );
}



void MacCoreFunctions::writeToNativeLoggingSystem( const QString& message, Logger::LogLevel loglevel )
{
	if( m_logHandle == nullptr )
	{
		return;
	}

	os_log_type_t logType = OS_LOG_TYPE_DEFAULT;

	switch( loglevel )
	{
	case Logger::LogLevel::Critical: logType = OS_LOG_TYPE_FAULT; break;
	case Logger::LogLevel::Error: logType = OS_LOG_TYPE_ERROR; break;
	case Logger::LogLevel::Info: logType = OS_LOG_TYPE_INFO; break;
	case Logger::LogLevel::Debug: logType = OS_LOG_TYPE_DEBUG; break;
	default: break;
	}

	os_log_with_type( m_logHandle, logType, "%{public}s", message.toUtf8().constData() );
}



StandardInputReader* MacCoreFunctions::createStandardInputReader(QObject* parent)
{
	auto reader = new StandardInputReader(parent);

	auto notifier = new QSocketNotifier(STDIN_FILENO, QSocketNotifier::Read, reader);
	QObject::connect(notifier, &QSocketNotifier::activated,
					 reader, [reader]() {
		reader->lineRead(QTextStream(stdin).readLine());
	});

	return reader;
}



void MacCoreFunctions::reboot()
{
	if( isRunningAsAdmin() )
	{
		QProcess::startDetached( QStringLiteral("/sbin/shutdown"), { QStringLiteral("-r"), QStringLiteral("now") } );
	}
	else
	{
		sendLoginWindowEvent( QStringLiteral("rest") );
	}
}



void MacCoreFunctions::powerDown( bool installUpdates )
{
	Q_UNUSED(installUpdates)

	if( isRunningAsAdmin() )
	{
		QProcess::startDetached( QStringLiteral("/sbin/shutdown"), { QStringLiteral("-h"), QStringLiteral("now") } );
	}
	else
	{
		sendLoginWindowEvent( QStringLiteral("shut") );
	}
}



void MacCoreFunctions::raiseWindow( QWidget* widget, bool stayOnTop )
{
	widget->activateWindow();
	widget->raise();

	if( stayOnTop )
	{
		const auto isVisible = widget->isVisible();
		const auto isFullscreen = widget->isFullScreen();

		widget->setWindowFlag( Qt::WindowStaysOnTopHint, true );

		if( isFullscreen )
		{
			widget->showFullScreen();
		}
		else if( isVisible )
		{
			widget->show();
		}
	}
}



void MacCoreFunctions::disableScreenSaver()
{
	if( m_displaySleepAssertionActive )
	{
		return;
	}

	IOPMAssertionID assertionId = kIOPMNullAssertionID;
	if( IOPMAssertionCreateWithName( kIOPMAssertionTypePreventUserIdleDisplaySleep, kIOPMAssertionLevelOn,
									 CFSTR("Veyon"), &assertionId ) == kIOReturnSuccess )
	{
		m_displaySleepAssertion = assertionId;
		m_displaySleepAssertionActive = true;
	}
	else
	{
		vWarning() << "could not create power management assertion";
	}
}



void MacCoreFunctions::restoreScreenSaverSettings()
{
	if( m_displaySleepAssertionActive )
	{
		IOPMAssertionRelease( m_displaySleepAssertion );
		m_displaySleepAssertionActive = false;
	}
}



void MacCoreFunctions::setSystemUiState( bool enabled )
{
	Q_UNUSED(enabled)
}



QString MacCoreFunctions::activeDesktopName()
{
	return {};
}



bool MacCoreFunctions::isRunningAsAdmin() const
{
	return getuid() == 0 || geteuid() == 0;
}



bool MacCoreFunctions::runProgramAsAdmin( const QString& program, const QStringList& parameters )
{
	// program and parameters are passed as script arguments and quoted by AppleScript itself so
	// nothing has to be escaped here; HOME and TMPDIR are reset so that the elevated process
	// does not create root-owned files in the user's home or temporary directory
	return runAppleScript( {
							   QStringLiteral("on run argv"),
							   QStringLiteral("set commandLine to \"/usr/bin/env HOME=/var/root TMPDIR=/tmp\""),
							   QStringLiteral("repeat with arg in argv"),
							   QStringLiteral("set commandLine to commandLine & \" \" & quoted form of (arg as text)"),
							   QStringLiteral("end repeat"),
							   QStringLiteral("do shell script commandLine with administrator privileges"),
							   QStringLiteral("end run")
						   },
						   QStringList( program ) + parameters ) == 0;
}



bool MacCoreFunctions::runProgramAsUser( const QString& program, const QStringList& parameters,
										 const QString& username, const QString& desktop,
										 const QByteArray& stdInData )
{
	Q_UNUSED(desktop)

	const auto pwEntry = getpwnam( username.toUtf8().constData() );
	if( pwEntry == nullptr )
	{
		vCritical() << "failed to resolve user" << username;
		return false;
	}

	const auto uid = pwEntry->pw_uid;
	const auto gid = pwEntry->pw_gid;

#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
	auto process = new QProcess;
	process->setChildProcessModifier( [uid, gid]() {
		const auto isRoot = getuid() == 0 || geteuid() == 0;
		if( isRoot && ( setgroups( 0, nullptr ) != 0 || setgid( gid ) != 0 || setuid( uid ) != 0 ) )
		{
			// never run the program with elevated privileges
			_exit( EXIT_FAILURE );
		}
	} );

	if( stdInData.isEmpty() == false )
	{
		QObject::connect( process, &QProcess::started, process, [=]() {
			process->write( stdInData );
			process->closeWriteChannel();
		} );
	}

	QObject::connect( process, &QProcess::finished, process, &QProcess::deleteLater );
	process->start( program, parameters );

	return true;
#else
	Q_UNUSED(program)
	Q_UNUSED(parameters)
	Q_UNUSED(uid)
	Q_UNUSED(gid)
	Q_UNUSED(stdInData)

	vCritical() << "not supported with Qt 5";
	return false;
#endif
}



QString MacCoreFunctions::genericUrlHandler() const
{
	return QStringLiteral( "/usr/bin/open" );
}



QString MacCoreFunctions::queryDisplayDeviceName(const QScreen& screen) const
{
	QStringList nameParts;
	nameParts.append(screen.manufacturer());
	nameParts.append(screen.model());
	nameParts.removeAll({});
	if(nameParts.isEmpty())
	{
		return screen.name();
	}

	return QStringLiteral("%1 [%2]").arg(nameParts.join(QLatin1Char(' ')), screen.name());
}



QString MacCoreFunctions::getApplicationName(ProcessId processId) const
{
	char name[2 * MAXCOMLEN + 1]{};
	if( proc_name( int(processId), name, sizeof(name) ) > 0 )
	{
		return QString::fromUtf8( name );
	}

	return {};
}



int MacCoreFunctions::runAppleScript( const QStringList& statements, const QStringList& arguments )
{
	QStringList osascriptArguments;
	for( const auto& statement : statements )
	{
		osascriptArguments.append( QStringLiteral("-e") );
		osascriptArguments.append( statement );
	}

	return QProcess::execute( QStringLiteral("/usr/bin/osascript"), osascriptArguments + arguments );
}



bool MacCoreFunctions::sendLoginWindowEvent( const QString& eventCode )
{
	// send raw Apple event of class 'aevt' (see AERegistry.h, e.g. 'rlgo' = really log out)
	// using AppleScript's chevron syntax: «event aevtrlgo»
	return runAppleScript( { QStringLiteral("tell application \"loginwindow\" to %1event aevt%2%3")
							 .arg( QChar(0x00AB) ).arg( eventCode ).arg( QChar(0x00BB) ) } ) == 0;
}
