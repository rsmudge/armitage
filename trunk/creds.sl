#
# Script to build SQL query for Metasploit creds model
#	1. Run this script
#	2. Use the output with db.creds/db.creds2 in src/msf/DatabaseImpl.java
#

# the different tables that contain origin information for our credentials
@origin = @('metasploit_credential_origin_manuals', 
	    'metasploit_credential_origin_imports',
	    'metasploit_credential_origin_sessions',
	    'metasploit_credential_origin_services',
	    'metasploit_credential_origin_cracked_passwords');

# the tables we will be pulling data from!
@tables = @('metasploit_credential_publics',
	    'metasploit_credential_privates',
	    'metasploit_credential_cores');

# what we want to go into each row that's returned. Goal is to stay db.creds compatible
%keys = %(
	user        => "metasploit_credential_publics.username",
	pass        => "metasploit_credential_privates.data",
	ptype       => "metasploit_credential_privates.type",
	#realm_key   => "metasploit_credential_realms.key",
	#realm_value => "metasploit_credential_realms.value",
	id          => "metasploit_credential_cores.id",
	realm_id    => "metasploit_credential_cores.realm_id");

# 
%withservice = %(
	host        => "host(hosts.address)",
	sname       => "services.name",
	port        => "services.port",
	proto       => "services.proto");

# 
%noservice = %(
	host        => "''",
	sname       => "''",
	port        => "0",
	proto       => "''");

%withsession = %(
	host        => "host(hosts.address)",
	sname       => "''",
	port        => "sessions.port",
	proto       => "''");

# map origin_type to tablename...
%origin_types = %(
	Metasploit::Credential::Origin::Session => "metasploit_credential_origin_sessions",
	Metasploit::Credential::Origin::Import  => "metasploit_credential_origin_imports",
	Metasploit::Credential::Origin::Service => "metasploit_credential_origin_services",
	Metasploit::Credential::Origin::Manual  => "metasploit_credential_origin_manuals",
	Metasploit::Credential::Origin::Cracked_Password => "metasploit_credential_origin_cracked_passwords");

# build a list of columns
sub columns {
	local('$key $value @r');
	foreach $key => $value ($1) {
		push(@r, "$value AS $key");
	}

	foreach $key => $value ($2) {
		push(@r, "$value AS $key");
	}

	return join(", ", @r);
}

# build a list of tables to query from
sub tables {
	local('@t $2');
	@t = copy(@tables);
	if ($2 == 1) {
		push(@t, "hosts");
		push(@t, "services");
	}
	else if ($2 == 2) {
		push(@t, "hosts");
		push(@t, "sessions");
	}
	push(@t, $1);
	return join(", ", @t);
}

sub clauses {
	local('@w $3');
	push(@w, "metasploit_credential_cores.origin_id = $1 $+ .id");
	push(@w, "metasploit_credential_cores.origin_type = ' $+ $2 $+ '");
	push(@w, "metasploit_credential_cores.public_id = metasploit_credential_publics.id");
	push(@w, "metasploit_credential_cores.private_id = metasploit_credential_privates.id");
#	push(@w, "metasploit_credential_cores.realm_id = metasploit_credential_realms.id");

	if ($3 == 1) {
		push(@w, "$1 $+ .service_id = services.id");
		push(@w, "services.host_id = hosts.id");
		push(@w, "hosts.workspace_id = \" + workspaceid + \"");
	}
	else if ($3 == 2) {
		push(@w, "$1 $+ .session_id = sessions.id");
		push(@w, "sessions.host_id = hosts.id");
		push(@w, "hosts.workspace_id = \" + workspaceid + \"");
	}
	return join(" AND ", @w);
}

#
# build our individual queries first...
#

@queries = @();

foreach $class => $table (%origin_types) {
	# pull host information!
	if ($table eq "metasploit_credential_origin_services") {
		$c = columns(%keys, %withservice);
		$t = tables($table, 1);
		$w = clauses($table, $class, 1);
	}
	# pull info here too
	else if ($table eq "metasploit_credential_origin_sessions") {
		$c = columns(%keys, %withsession);
		$t = tables($table, 2);
		$w = clauses($table, $class, 2);
	}
	# do not pull host information
	else {
		$c = columns(%keys, %noservice);
		$t = tables($table);
		$w = clauses($table, $class);
	}

	push(@queries, "SELECT $c FROM $t WHERE $w");
}

println(join(" UNION ", @queries));
