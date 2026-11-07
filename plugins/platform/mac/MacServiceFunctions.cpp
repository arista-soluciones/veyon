/*
 * MacServiceFunctions.cpp - implementation of MacServiceFunctions class
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

#include <QFile>
#include <QProcess>

#include "MacServiceFunctions.h"
#include "ProcessHelper.h"


QString MacServiceFunctions::veyonServiceName() const
{
	return QStringLiteral("io.veyon.service");
}



bool MacServiceFunctions::isRegistered( const QString& name )
{
	return QFile::exists( launchDaemonFilePath( name ) );
}



bool MacServiceFunctions::isRunning( const QString& name )
{
	return ProcessHelper( QStringLiteral("/bin/launchctl"), { QStringLiteral("print"), serviceTarget( name ) } )
			.runAndReadAll().contains( "state = running" );
}



bool MacServiceFunctions::start( const QString& name )
{
	if( isRegistered( name ) == false )
	{
		return false;
	}

	// make sure the service is loaded (bootstrap fails harmlessly if it already is)
	launchctl( { QStringLiteral("bootstrap"), QStringLiteral("system"), launchDaemonFilePath( name ) } );

	return launchctl( { QStringLiteral("kickstart"), serviceTarget( name ) } ) == 0;
}



bool MacServiceFunctions::stop( const QString& name )
{
	if( isRegistered( name ) == false )
	{
		return false;
	}

	return launchctl( { QStringLiteral("bootout"), serviceTarget( name ) } ) == 0;
}



bool MacServiceFunctions::install( const QString& name, const QString& filePath,
								   StartMode startMode, const QString& displayName )
{
	Q_UNUSED(name)
	Q_UNUSED(filePath)
	Q_UNUSED(startMode)
	Q_UNUSED(displayName)

	vCritical() << "installing services is not supported on macOS";

	return false;
}



bool MacServiceFunctions::uninstall( const QString& name )
{
	Q_UNUSED(name)

	vCritical() << "uninstalling services is not supported on macOS";

	return false;
}



bool MacServiceFunctions::setStartMode( const QString& name, StartMode startMode )
{
	// nothing to configure if the service is not installed - must not fail as
	// ConfigurationManager::applyConfiguration() would fail as well otherwise
	if( isRegistered( name ) == false )
	{
		return true;
	}

	return launchctl( { startMode == StartMode::Auto ? QStringLiteral("enable") : QStringLiteral("disable"),
						serviceTarget( name ) } ) == 0;
}



bool MacServiceFunctions::runAsService( const QString& name, const ServiceEntryPoint& serviceEntryPoint )
{
	Q_UNUSED(name)

	// launchd runs daemons as regular processes
	serviceEntryPoint();

	return true;
}



void MacServiceFunctions::manageServerInstances()
{
	vCritical() << "the Veyon Service is not supported on macOS";
}



QString MacServiceFunctions::launchDaemonFilePath( const QString& name )
{
	return QStringLiteral("/Library/LaunchDaemons/%1.plist").arg( name );
}



QString MacServiceFunctions::serviceTarget( const QString& name )
{
	return QStringLiteral("system/%1").arg( name );
}



int MacServiceFunctions::launchctl( const QStringList& arguments )
{
	return QProcess::execute( QStringLiteral("/bin/launchctl"), arguments );
}
