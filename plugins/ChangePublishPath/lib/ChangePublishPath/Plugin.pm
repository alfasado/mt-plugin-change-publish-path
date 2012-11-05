package ChangePublishPath::Plugin;

use strict;

sub _pre_run {
    my $app = MT->instance;
    if ( ( ref $app ) !~ m/^MT::App::/ ) {
        return 1;
    }
    if ( $app->mode eq 'start_rebuild' ) {
        if (! $app->param( 'change_publish_path' ) ) {
            return 1;
        }
        my $plugin = $app->component( 'ChangePublishPath' );
        my $blog_id = $app->blog->id;
        my $outpath = $plugin->get_config_value( 'changepublishpath', 'blog:' . $blog_id );
        my $copy_asset = $plugin->get_config_value( 'cpp_copy_asset', 'blog:' . $blog_id );
        if ( (! $outpath ) || (! $copy_asset ) ) {
            return 1;
        }
        my $blogpath = $app->blog->site_path;
        $outpath =~ s!/$!!;
        $blogpath =~ s!/$!!;
        require MT::Asset;
        my $iter = MT::Asset->load_iter( { blog_id => $blog_id, class => '*' } );
        require MT::FileMgr;
        my $fmgr = MT::FileMgr->new( 'Local' ) or die MT::FileMgr->errstr;
        while ( my $asset = $iter->() ) {
            my $from = $asset->file_path;
            my $to = $from;
            my $search = quotemeta( $blogpath );
            $to =~ s/^$search/$outpath/;
            unless ( $fmgr->exists( $from ) ) {
                next;
            }
            my $copy = 1;
            if ( $fmgr->exists( $to ) ) {
                my $ts_to = ( stat $to )[ 9 ];
                my $ts_from = ( stat $from )[ 9 ];
                if ( $ts_from == $ts_to ) {
                    $copy = 0;
                }
            }
            if ( $copy ) {
                my $path = File::Basename::dirname( $to );
                $path =~ s!/$!! unless $path eq '/';
                unless ( $fmgr->exists( $path ) ) {
                    if (! $fmgr->mkpath( $path ) ) {
                        MT->log( MT->translate( "Error making path '[_1]': [_2]", $path, $fmgr->errstr ) );
                        next;
                    }
                }
                if ( File::Copy::Recursive::rcopy ( $from, $to ) ) {
                    MT->log( $plugin->translate( "Moving asset '[_1]' failed: [_2]", $from, $fmgr->errstr ) );
                    next;
                }
                my $atime = ( stat $from )[ 8 ];
                my $mtime = ( stat $from )[ 9 ];
                utime( $atime, $mtime, $to );
            }
        }
    }
    return 1;
}

sub _rebuild_confirm {
    my ( $cb, $app, $param, $tmpl ) = @_;
    my $plugin = $app->component( 'ChangePublishPath' );
    my $outpath = $plugin->get_config_value( 'changepublishpath', 'blog:' . $app->blog->id );
    if (! $outpath ) {
        return 1;
    }
    my $pointer_field = $tmpl->getElementById( 'dbtype' );
    my $screen_label = $plugin->get_config_value( 'cpp_screen_text', 'blog:' . $app->blog->id );
    if (! $screen_label ) {
        $screen_label = $plugin->translate( 'Change publish path' );
    }
    my $innerHTML = <<MTML;
<__trans_section component="ChangePublishPath">
<p>
    <label id="change_publish_path-wrapper"><input type="checkbox" id="change_publish_path" name="change_publish_path" value="1" /> $screen_label </label>
</p>
MTML
    $pointer_field->innerHTML( $pointer_field->innerHTML. $innerHTML );
}

sub _rebuilding_source {
    my ( $cb, $app, $tmpl ) = @_;
    my $new = '<mt:if name="change_publish_path">&change_publish_path=1</mt:if>';
    $$tmpl =~ s/(__mode=rebuild)/$1$new/;
}

sub _rebuilding {
    my ( $cb, $app, $param, $tmpl ) = @_;
    $param->{ change_publish_path } = $app->param( 'change_publish_path' );
}

sub _build_page {
    my ( $cb, %args ) = @_;
    my $app = MT->instance;
    if ( ( ref $app ) !~ m/^MT::App::/ ) {
        return 1;
    }
    if (! $app->param( 'change_publish_path' ) ) {
        return 1;
    }
    my $plugin = MT->component( 'ChangePublishPath' );
    my $file = $args{ File };
    my $blog = $args{ Blog };
    my $outpath = $plugin->get_config_value( 'changepublishpath', 'blog:' . $blog->id );
    if (! $outpath ) {
        return 1;
    }
    my $blogpath = $blog->site_path;
    $outpath =~ s!/$!!;
    $blogpath =~ s!/$!!;
    my $search = quotemeta( $blogpath );
    $file =~ s/^$search/$outpath/;
    require MT::FileMgr;
    my $fmgr = MT::FileMgr->new( 'Local' ) or die MT::FileMgr->errstr;
    if (! $fmgr->exists( $args{ File } ) ) {
        MT->request( 'CPP:' . $args{ File }, $file );
    } else {
        my $orig_html = $args{ Content };
        my $html = $args{ Content };
        $html = $$html;
        my $path = File::Basename::dirname( $file );
        $path =~ s!/$!! unless $path eq '/';
        unless ( $fmgr->exists( $path ) ) {
            if (! $fmgr->mkpath( $path ) ) {
                MT->log( MT->translate( "Error making path '[_1]': [_2]", $path, $fmgr->errstr ) );
                return 1;
            }
        }
        my $old = $fmgr->get_data( $file );
        $$orig_html = $old;
        unless ( $fmgr->content_is_updated( $file, \$html ) ) {
            return 1;
        }
        my $use_temp_files = 1;
        if ( MT->config( 'NoTempFiles' ) ) {
            $use_temp_files = 0;
        }
        my $temp_file = $use_temp_files ? "$file.new" : $file;
        unless ( defined $fmgr->put_data( $html, $temp_file ) ) {
            MT->log( MT->translate( "Writing to '[_1]' failed: [_2]", $temp_file, $fmgr->errstr ) );
            return 1;
        }
        if ( $use_temp_files ) {
            if (! $fmgr->rename( $temp_file, $file ) ) {
                MT->log( MT->translate( "Renaming tempfile '[_1]' failed: [_2]", $temp_file, $fmgr->errstr ) );
                return 1;
            }
        }
        MT->run_callbacks(
            'build_file',
            \%args,
        );
    }
    return 1;
}

sub _build_file {
    my ( $cb, %args ) = @_;
    my $app = MT->instance;
    if ( ( ref $app ) !~ m/^MT::App::/ ) {
        return 1;
    }
    if (! $app->param( 'change_publish_path' ) ) {
        return 1;
    }
    my $to = MT->request( 'CPP:' . $args{ File } );
    return 1 unless $to;
    my $from = $args{ File };
    require MT::FileMgr;
    my $fmgr = MT::FileMgr->new( 'Local' ) or die MT::FileMgr->errstr;
    my $path = File::Basename::dirname( $to );
    $path =~ s!/$!! unless $path eq '/';
    unless ( $fmgr->exists( $path ) ) {
        if (! $fmgr->mkpath( $path ) ) {
            MT->log( MT->translate( "Error making path '[_1]': [_2]", $path, $fmgr->errstr ) );
            return 1;
        }
    }
    $fmgr->rename( $from, $to );
    return 1;
}

sub _rebuilt_source {
    my ( $cb, $app, $tmpl ) = @_;
    if (! $app->param( 'change_publish_path' ) ) {
        return 1;
    }
    my $blog = $app->blog;
    my $plugin = $app->component( 'ChangePublishPath' );
    my $outpath = $plugin->get_config_value( 'changepublishpath', 'blog:' . $blog->id );
    if (! $outpath ) {
        return 1;
    }
    my $remove_file = $plugin->get_config_value( 'cpp_remove_file', 'blog:' . $blog->id );
    if (! $remove_file ) {
        return 1;
    }
    my $blogpath = $blog->site_path;
    $outpath =~ s!/$!!;
    $blogpath =~ s!/$!!;
    my $search = quotemeta( $outpath );
    my @out_files;
    require File::Find;
    File::Find::find ( sub { push ( @out_files, $File::Find::name ) unless (/^\./) || ! -f; }, $outpath );
    require MT::FileMgr;
    my $fmgr = MT::FileMgr->new( 'Local' ) or die MT::FileMgr->errstr;
    for my $file ( @out_files ) {
        my $orig = $file;
        $orig =~ s/^$search/$blogpath/;
        unless ( $fmgr->exists( $orig ) ) {
            $fmgr->delete( $file );
        }
    }
}

1;