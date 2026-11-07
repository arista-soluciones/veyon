/*
 * MacNetworkFunctions.cpp - implementation of MacNetworkFunctions class
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

#include <ifaddrs.h>
#include <net/if.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <sys/socket.h>
#include <sysexits.h>

#include <QHostAddress>
#include <QProcess>

#include "MacNetworkFunctions.h"
#include "ProcessHelper.h"


MacNetworkFunctions::PingResult MacNetworkFunctions::ping(const QString& hostAddress)
{
	QProcess pingProcess;

	// ping only handles IPv4 on macOS while ping6 does not support a timeout option
	if( QHostAddress( hostAddress ).protocol() == QAbstractSocket::IPv6Protocol )
	{
		pingProcess.start( QStringLiteral("/sbin/ping6"), { QStringLiteral("-c"), QStringLiteral("1"), hostAddress } );
	}
	else
	{
		pingProcess.start( QStringLiteral("/sbin/ping"), { QStringLiteral("-c"), QStringLiteral("1"),
														   QStringLiteral("-t"), QString::number( std::max( 1, PingTimeout / 1000 ) ),
														   hostAddress } );
	}

	if( pingProcess.waitForFinished( PingProcessTimeout ) == false )
	{
		pingProcess.kill();
		pingProcess.waitForFinished();
		return PingResult::TimedOut;
	}

	switch( pingProcess.exitCode() )
	{
	case EX_OK: return PingResult::ReplyReceived;
	case 2: return PingResult::TimedOut; // packet sent but no reply received
	case EX_NOHOST: return PingResult::NameResolutionFailed;
	default:
		break;
	}

	return PingResult::Unknown;
}



bool MacNetworkFunctions::configureFirewallException( const QString& applicationPath, const QString& description, bool enabled )
{
	Q_UNUSED(applicationPath)
	Q_UNUSED(description)
	Q_UNUSED(enabled)

	// the macOS application firewall asks the user when a program wants to accept incoming connections
	return true;
}



bool MacNetworkFunctions::configureSocketKeepalive( Socket socket, bool enabled, int idleTime, int interval, int probes )
{
#ifdef TCP_KEEPIDLE
	static constexpr int KeepIdleOption = TCP_KEEPIDLE;
#else
	static constexpr int KeepIdleOption = TCP_KEEPALIVE; // macOS name of TCP_KEEPIDLE
#endif

	int optval;
	socklen_t optlen = sizeof(optval);
	auto fd = static_cast<int>( socket );

	optval = enabled ? 1 : 0;
	if( setsockopt( fd, SOL_SOCKET, SO_KEEPALIVE, &optval, optlen ) < 0 )
	{
		vWarning() << "could not set SO_KEEPALIVE";
		return false;
	}

	optval = std::max<int>( 1, idleTime / 1000 );
	if( setsockopt( fd, IPPROTO_TCP, KeepIdleOption, &optval, optlen ) < 0 )
	{
		vWarning() << "could not set TCP_KEEPALIVE";
		return false;
	}

	optval = std::max<int>( 1, interval / 1000 );
	if( setsockopt( fd, IPPROTO_TCP, TCP_KEEPINTVL, &optval, optlen ) < 0 )
	{
		vWarning() << "could not set TCP_KEEPINTVL";
		return false;
	}

	optval = probes;
	if( setsockopt( fd, IPPROTO_TCP, TCP_KEEPCNT, &optval, optlen ) < 0 )
	{
		vWarning() << "could not set TCP_KEEPCNT";
		return false;
	}

	return true;
}



QNetworkInterface MacNetworkFunctions::defaultRouteNetworkInterface()
{
	for( const auto& addressFamily : { QStringLiteral("-inet"), QStringLiteral("-inet6") } )
	{
		const auto routeInfo = ProcessHelper( QStringLiteral("/sbin/route"),
											  { QStringLiteral("-n"), QStringLiteral("get"), addressFamily, QStringLiteral("default") } )
							   .runAndReadAll().split('\n');

		for( const auto& line : routeInfo )
		{
			const auto keyValue = line.trimmed().split(':');
			if( keyValue.size() == 2 && keyValue[0] == QByteArrayLiteral("interface") )
			{
				return QNetworkInterface::interfaceFromName( QString::fromLatin1( keyValue[1].trimmed() ) );
			}
		}
	}

	return {};
}



int MacNetworkFunctions::networkInterfaceSpeedInMBitPerSecond(const QNetworkInterface& networkInterface)
{
	if( networkInterface.isValid() == false )
	{
		return 0;
	}

	struct ifaddrs* interfaceAddresses = nullptr;
	if( getifaddrs( &interfaceAddresses ) != 0 )
	{
		return 0;
	}

	const auto interfaceName = networkInterface.name().toUtf8();
	int speed = 0;

	for( auto ifa = interfaceAddresses; ifa != nullptr; ifa = ifa->ifa_next )
	{
		if( ifa->ifa_addr && ifa->ifa_addr->sa_family == AF_LINK && ifa->ifa_data &&
			qstrcmp( ifa->ifa_name, interfaceName.constData() ) == 0 )
		{
			speed = int( static_cast<const struct if_data *>( ifa->ifa_data )->ifi_baudrate / 1000000 );
			break;
		}
	}

	freeifaddrs( interfaceAddresses );

	return speed;
}
