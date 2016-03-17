package Net::Amazon::SNS::Signature;
use strict; use warnings;

use Carp;
use Crypt::OpenSSL::RSA;
use Crypt::OpenSSL::X509;
use MIME::Base64;
use LWP::UserAgent;

=head1 NAME

Net::Amazon::SNS::Signature

=head1 DESCRIPTION

For the verification of Amazon SNS messages

=head1 USAGE

    # Will download the signature certificate from SigningCertURL attribute of $message_ref
    # use LWP::UserAgent
    my $sns_signature = Net::Amazon::SNS::Signature->new();
    if ( $sns_signature->verify( $message_ref ) ){ ... }

    # Will automatically download the certificate using your own user_agent ( supports ->get returns HTTP::Response )
    my $sns_signature = Net::Amazon::SNS::Signature->new( user_agent => $my_user_agent );
    if ( $sns_signature->verify( $message_ref ) ){ ... }

    # Provide the certificate yourself
    my $sns_signature = Net::Amazon::SNS::Signature->new()
    if ( $sns_signature->verify({ message => $message_ref, certificate => $x509_cert }) ) { ... }

=head2 verify

Call to verify the message, C<$message> is required as first parameter, C<$cert> is
optional and should be a raw x509 certificate as downloaded from Amazon.

=cut

sub verify {
    my ( $self, $message, $cert ) = @_;

    my $signature = MIME::Base64::decode_base64($message->{Signature})
        or carp( "Signature is a required attribute of message" );
    my $string = $self->build_sign_string( $message );
    my $public_key = $cert ? $self->_key_from_cert( $cert ) :
        $self->_public_key_from_url( $message->{SigningCertURL} );

    my $rsa = Crypt::OpenSSL::RSA->new_public_key( $public_key );
    return $rsa->verify($string, $signature);
}

=head2 build_sign_string

Given a C<$message_ref> will return a formatted string ready to be signed.

Usage:

    my $sign_string = $this->build_sign_string({
        Message     => 'Hello',
        MessageId   => '12345',
        Subject     => 'I am a message',
        Timestamp   => '2016-01-20T14:37:01Z',
        TopicArn    => 'xyz123',
        Type        => 'Notification'
    });

=cut

sub build_sign_string {
    my ( $self, $message ) = @_;

    my @keys = ( qw/Message MessageId/, ( defined($message->{Subject}) ? 'Subject' : () ), qw/Timestamp TopicArn Type/ );
    defined($message->{$_}) or carp( sprintf( "%s is required", $_ ) ) for @keys;
    return join( "\n", ( map { ( $_, $message->{$_} ) } @keys ), "" );
}

sub new {
    my ( $class, $args_ref ) = @_;
    return bless {
        defined($args_ref->{user_agent}) ? ( user_agent => $args_ref->{user_agent} ) : ()
    }, $class;
}

sub _public_key_from_url {
    my ( $self, $url ) = @_;
    my $response = $self->user_agent->get( $url );
    my $content = $response->decoded_content;
    return $self->_key_from_cert( $content );
}

sub _key_from_cert {
    my ( $self, $cert ) = @_;
    my $x509 = Crypt::OpenSSL::X509->new_from_string(
        $cert, Crypt::OpenSSL::X509::FORMAT_PEM
    );
    return $x509->pubkey;
}

sub user_agent {
    my ( $self ) = @_;
    unless ( defined( $self->{user_agent} ) ){
        $self->{user_agent} = LWP::UserAgent->new();
    }
    return $self->{user_agent};
}

1;
