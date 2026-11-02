/*
 * MacUserFunctions.cpp - implementation of MacUserFunctions class
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

#include <cstdlib>
#include <cstring>
#include <grp.h>
#include <pwd.h>
#include <unistd.h>
#include <sys/stat.h>

#include <security/pam_appl.h>

#include "MacCoreFunctions.h"
#include "MacUserFunctions.h"
#include "ProcessHelper.h"


namespace {

struct PamCredentials
{
	QByteArray username;
	QByteArray password;
};


void freePamResponses( struct pam_response* responses, int count )
{
	for( int i = 0; i < count; ++i )
	{
		if( responses[i].resp )
		{
			// wipe passwords - volatile prevents the compiler from optimizing the loop away
			for( volatile char* c = responses[i].resp; *c; ++c )
			{
				*c = 0;
			}
			free( responses[i].resp );
		}
	}
	free( responses );
}


int pamConversation( int messageCount, const struct pam_message** messages, struct pam_response** responses, void* appData )
{
	if( messageCount <= 0 || appData == nullptr )
	{
		return PAM_CONV_ERR;
	}

	const auto credentials = static_cast<const PamCredentials *>( appData );

	auto replies = static_cast<struct pam_response *>( calloc( size_t(messageCount), sizeof(struct pam_response) ) );
	if( replies == nullptr )
	{
		return PAM_BUF_ERR;
	}

	for( int i = 0; i < messageCount; ++i )
	{
		switch( messages[i]->msg_style )
		{
		case PAM_PROMPT_ECHO_ON:
			replies[i].resp = strdup( credentials->username.constData() );
			break;
		case PAM_PROMPT_ECHO_OFF:
			replies[i].resp = strdup( credentials->password.constData() );
			break;
		case PAM_TEXT_INFO:
		case PAM_ERROR_MSG:
			break;
		default:
			freePamResponses( replies, i );
			return PAM_CONV_ERR;
		}
	}

	*responses = replies;

	return PAM_SUCCESS;
}


bool isRealUser( const struct passwd* pwEntry )
{
	const auto shell = QString::fromUtf8( pwEntry->pw_shell );
	return !( shell.endsWith( QLatin1String("/false") ) ||
			  shell.endsWith( QLatin1String("/true") ) ||
			  shell.endsWith( QLatin1String("/nologin") ) );
}

}



QString MacUserFunctions::queryCurrentUserProperty(UserProperty property)
{
	const auto pwEntry = getpwuid( getuid() );
	if( pwEntry == nullptr || isRealUser( pwEntry ) == false )
	{
		return {};
	}

	switch( property )
	{
	case UserProperty::LoginName: return QString::fromUtf8( pwEntry->pw_name );
	case UserProperty::FullName: return QString::fromUtf8( pwEntry->pw_gecos ).split( QLatin1Char(',') ).first();
	case UserProperty::None: break;
	}

	return {};
}



QStringList MacUserFunctions::userGroups( bool queryDomainGroups )
{
	Q_UNUSED(queryDomainGroups)

	static const QStringList ignoredGroups{
		QStringLiteral("accessibility"),
		QStringLiteral("bin"),
		QStringLiteral("certusers"),
		QStringLiteral("daemon"),
		QStringLiteral("dialer"),
		QStringLiteral("group"),
		QStringLiteral("kmem"),
		QStringLiteral("mail"),
		QStringLiteral("network"),
		QStringLiteral("nobody"),
		QStringLiteral("nogroup"),
		QStringLiteral("operator"),
		QStringLiteral("owner"),
		QStringLiteral("procmod"),
		QStringLiteral("procview"),
		QStringLiteral("sys"),
		QStringLiteral("tty"),
		QStringLiteral("utmpx"),
		QStringLiteral("wheel"),
	};

	QStringList groupList;

	setgrent();
	while( const auto group = getgrent() )
	{
		const auto groupName = QString::fromUtf8( group->gr_name );

		// skip internal service groups such as "_www" or "com.apple.access_ssh"
		if( groupName.isEmpty() ||
			groupName.startsWith( QLatin1Char('_') ) ||
			groupName.startsWith( QLatin1String("com.apple.") ) ||
			ignoredGroups.contains( groupName ) )
		{
			continue;
		}

		groupList.append( groupName );
	}
	endgrent();

	groupList.removeDuplicates();
	groupList.sort();

	return groupList;
}



QStringList MacUserFunctions::groupsOfUser( const QString& username, bool queryDomainGroups )
{
	Q_UNUSED(queryDomainGroups)

	// id resolves all memberships (including nested and directory groups) through
	// opendirectoryd - query numeric IDs as group names may contain spaces
	const auto groupIds = ProcessHelper( QStringLiteral("/usr/bin/id"), { QStringLiteral("-G"), username } )
						  .runAndReadAll().simplified().split(' ');

	QStringList groupList;
	groupList.reserve( groupIds.size() );

	for( const auto& groupId : groupIds )
	{
		bool ok = false;
		const auto gid = gid_t( groupId.toUInt( &ok ) );
		if( ok == false )
		{
			continue;
		}

		const auto group = getgrgid( gid );
		if( group && group->gr_name )
		{
			groupList.append( QString::fromUtf8( group->gr_name ) );
		}
	}

	groupList.removeDuplicates();

	return groupList;
}



QString MacUserFunctions::userGroupSecurityIdentifier(const QString& groupName)
{
	const auto group = getgrnam( groupName.toUtf8().constData() );
	if( group )
	{
		return QString::number( group->gr_gid );
	}

	return {};
}



bool MacUserFunctions::isAnyUserLoggedOn()
{
	// the console device is owned by the user logged in at the login window
	struct stat consoleStat{};
	return stat( "/dev/console", &consoleStat ) == 0 && consoleStat.st_uid != 0;
}



bool MacUserFunctions::prepareLogon( const QString& username, const Password& password )
{
	Q_UNUSED(username)
	Q_UNUSED(password)

	vWarning() << "logging on users is not supported on macOS";

	return false;
}



bool MacUserFunctions::performLogon( const QString& username, const Password& password )
{
	Q_UNUSED(username)
	Q_UNUSED(password)

	vWarning() << "logging on users is not supported on macOS";

	return false;
}



void MacUserFunctions::logoff()
{
	MacCoreFunctions::sendLoginWindowEvent( QStringLiteral("rlgo") );
}



bool MacUserFunctions::authenticate( const QString& username, const Password& password )
{
	// the checkpw service only verifies the password via opendirectoryd - fall back to
	// the login service which is present on every system
	const auto pamService = QFile::exists( QStringLiteral("/etc/pam.d/checkpw") ) ? "checkpw" : "login";

	PamCredentials credentials{ username.toUtf8(), password.toByteArray() };
	const struct pam_conv conversation{ pamConversation, &credentials };

	pam_handle_t* pamHandle = nullptr;
	auto result = pam_start( pamService, credentials.username.constData(), &conversation, &pamHandle );

	if( result == PAM_SUCCESS )
	{
		// required for modules configured with use_first_pass
		result = pam_set_item( pamHandle, PAM_AUTHTOK, credentials.password.constData() );
	}

	if( result == PAM_SUCCESS )
	{
		result = pam_authenticate( pamHandle, PAM_SILENT );
	}

	if( result == PAM_SUCCESS )
	{
		result = pam_acct_mgmt( pamHandle, PAM_SILENT );
	}

	if( result != PAM_SUCCESS )
	{
		vWarning() << "authentication of user" << username << "failed:"
				   << ( pamHandle ? pam_strerror( pamHandle, result ) : "pam_start() failed" );
	}

	if( pamHandle )
	{
		pam_end( pamHandle, result );
	}

	credentials.password.fill( 0 );

	return result == PAM_SUCCESS;
}
