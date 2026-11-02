/*
 * MacSessionFunctions.cpp - implementation of MacSessionFunctions class
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

#include <QCoreApplication>
#include <QProcessEnvironment>
#include <QSettings>

#include <sys/stat.h>

#include "MacSessionFunctions.h"


MacSessionFunctions::SessionId MacSessionFunctions::currentSessionId()
{
	return DefaultSessionId;
}



MacSessionFunctions::SessionUptime MacSessionFunctions::currentSessionUptime() const
{
	return InvalidSessionUptime;
}



QString MacSessionFunctions::currentSessionClientAddress() const
{
	return {};
}



QString MacSessionFunctions::currentSessionClientName() const
{
	return {};
}



QString MacSessionFunctions::currentSessionHostName() const
{
	return {};
}



QString MacSessionFunctions::currentSessionType() const
{
	return QStringLiteral("macos");
}



bool MacSessionFunctions::currentSessionHasUser() const
{
	// the console device is owned by the user logged in at the login window
	struct stat consoleStat{};
	return stat( "/dev/console", &consoleStat ) == 0 && consoleStat.st_uid != 0;
}



MacSessionFunctions::EnvironmentVariables MacSessionFunctions::currentSessionEnvironmentVariables() const
{
	EnvironmentVariables environmentVariables;

	const auto environment = QProcessEnvironment::systemEnvironment();
	for( const auto& key : environment.keys() )
	{
		environmentVariables[key] = environment.value( key );
	}

	return environmentVariables;
}



QVariant MacSessionFunctions::querySettingsValueInCurrentSession(const QString& key) const
{
	return QSettings(QSettings::UserScope, QCoreApplication::organizationName(), QCoreApplication::applicationName()).value(key);
}
