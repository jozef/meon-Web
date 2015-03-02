package meon::Web::Filter::CategoryProduct;

use Moose;
use 5.010;

has 'dom' => (is=>'ro',isa=>'XML::LibXML::Document',required=>1);
has 'include_node' => (is=>'ro',isa=>'XML::LibXML::Node',required=>1);
has '_all_items' => (is=>'ro',isa=>'HashRef',default=>sub { {} });

use meon::Web::Util;
use meon::Web::ResponseXML;

our $HREF_BASE = '/c';

sub apply {
    my ($self) = @_;
    my $dom = $self->dom;
    my $xpc = meon::Web::Util->xpc;

    my ($current_ident_el) = $xpc->findnodes('//w:current-category-product',$self->include_node);
    die 'missing w:current-category-product in include configuration'
        unless $current_ident_el;
    $current_ident_el = $current_ident_el->cloneNode;
    $dom->documentElement->appendChild($current_ident_el);

    my ($breadcrumb_el)    = $xpc->findnodes('//w:category-product-breadcrumb',$self->include_node);
    die 'missing w:category-product-breadcrumb in include configuration'
        unless $breadcrumb_el;
    $breadcrumb_el = $breadcrumb_el->cloneNode;
    $dom->documentElement->appendChild($breadcrumb_el);

    my $current_ident   = $current_ident_el->getAttribute('ident');
    my $breadcrumb_href = $breadcrumb_el->getAttribute('href');
    my @breadcrumb_idents = split('/',$breadcrumb_href);

    my $all_items = $self->_all_items;
    my @all_idents;
    my (@category_products) =
        $xpc->findnodes('/w:category-products/w:category-product',$dom);

    foreach my $category_product_el (@category_products) {
        my $ident = $category_product_el->getAttribute('ident');
        push(@all_idents, $ident);
        $all_items->{$ident} = $category_product_el;
    }
    die 'no home category' unless $all_items->{'home'};
    $all_items->{'home'}->setAttribute('href' => $HREF_BASE);

    while (@breadcrumb_idents) {
        my $current_category_ident = shift(@breadcrumb_idents);
        my $next_category_ident    = $breadcrumb_idents[0];

        my $current_category = $all_items->{$current_category_ident};
        if (
            !$current_category
            || (
                $next_category_ident
                && !$self->_has_subcategory($current_category, $next_category_ident)
            )
        ) {
            return {
                error  => 'category path not found',
                status => 404,
            };
        }

        my $breadcrumb_item_el = meon::Web::ResponseXML->new(dom => $dom)->create_element('breadcrumb-item');
        $breadcrumb_item_el->setAttribute(ident=>$current_category->getAttribute('ident'));
        $breadcrumb_el->appendText("\n");
        $breadcrumb_el->appendChild($breadcrumb_item_el);
    }

    # TODO make $self->_set_href() that honors @breadcrumb_idents;

    $self->_set_href($all_items->{'home'});
    $all_items->{'home'}->setAttribute('href' => '/');

    return {
        dom => $dom,
    };
}

sub _has_subcategory {
    my ($self, $item, $sub_ident) = @_;
    my $xpc = meon::Web::Util->xpc;
    my @nodes = $xpc->findnodes(
        'w:subcategory-products/w:category-product[@ident="'.$sub_ident.'"]',
        $item
    );
    return scalar(@nodes);
}

sub _set_href {
    my ($self, $item) = @_;
    my $dom = $self->dom;
    my $all_items = $self->_all_items;
    my $href = $item->getAttribute('href');
    die 'has no href' unless $href;

    my $xpc = meon::Web::Util->xpc;

    my (@category_products) =
        $xpc->findnodes('w:subcategory-products/w:category-product',$item);

    my @to_recurse;
    foreach my $category_product_el (@category_products) {
        my $ident = $category_product_el->getAttribute('ident');
        my $sub_item = $all_items->{$ident};
        next unless $sub_item;                      # missing/extra items
        next if $sub_item->getAttribute('href');    # already set
        my $sub_href = join('/', $href, $ident);
        $sub_item->setAttribute('href' => $sub_href);
        push(@to_recurse, $sub_item);
    }

    foreach my $sub_item (@to_recurse) {
        $self->_set_href($sub_item);
    }
}

1;
