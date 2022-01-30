#Quais as cidades com maiores quantidades de pedidos?

#Para responder a esta pergunta, irei utilizar as tabelas clientes e pedidos, dado que na tabela clientes, 
#entre outras informações, encontramos suas cidades e estados, e com isso, conseguimos fazer sua junção com 
#a tabela pedidos através da chave customer_id.

#Antes de começar, é importante fazermos a verificação de valores nulos na coluna customer_id das duas tabelas
#para que não tenhamos problemas na hora de uni-las. 

select customer_unique_id, count(distinct customer_unique_id) as soma_nulos from olist.clientes
where customer_id is null
group by 1
order by 2 desc;

select order_id, count(distinct order_id) as soma_nulos from olist.pedidos
where customer_id is null
group by 1
order by 2 desc;

#Logo, pode-se verificar a não existência de valores nulos na coluna customer_id

#Agora, vamos verificar se há linhas duplicadas nas duas bases

select customer_id, count(*) from olist.clientes
group by 1
order by 2 desc;

select order_id, count(*) from olist.pedidos
group by 1
order by 2 desc;

#O que também nos mostra que não há valores duplicados em ambas as tabelas

#E agora faremos a consulta das duas tabelas a fim de responder a primeira pergunta no case.

select CONCAT(upper(substr(customer_city,1))," - ", customer_state) AS CIDADE, count(distinct order_id) AS TOTAL 
from olist.clientes c
left join olist.pedidos p on c.customer_id = p.customer_id
group by 1
order by 2 desc;

#Quais cidades com maiores médias no valor do pedido?

#Na tabela itens, podemos perceber que cada linha é o item de um pedido, com isso, um pedido pode aparecer 
#em várias linhas, sendo o que diferencia uma da outra é o item do pedido (identificado pela coluna order_item_id).

With mediavalue (cidades_clientes, estado_clientes, total_pedidos, contagem_pedidos) as
(
select upper(substr(c.customer_city,1))as cidades_clientes, c.customer_state as estado_clientes, 
sum(i.price) as total_pedidos, 
count(distinct(p.order_id)) as contagem_pedidos 
from olist.pedidos p
join olist.clientes c on p.customer_id = c.customer_id
left join olist.itens i on p.order_id=i.order_id 
where order_status = "delivered"
group by 1,2
order by 4 desc
)
select *, total_pedidos/contagem_pedidos as media_valor
from mediavalue;


#O frete representa quanto do valor do pedido?

#Para responder a esta pergunta, foi preciso utilizar a tabela itens onde se encontram os valores envolvidos
#Primeiramente, na tabela itens foi feito o levantamento do total pago em cada item, bem como o valor de frete 
#envolvido. Para encontrar o estes valores totais, foi preciso fazer a soma deles por pedido visto que cada linha 
#desta representa 1 item de cada pedido, assim como o valor de seu respectivo frete.
#A partir disso, foi preciso utlizar o recurso de Common Table Expression (CTE) para se calcular o quanto que o frete 
#representa do valor total do pedido, calculado com os valores encontrados no passo anterior.
 
create table percent_frete(
with percentfrete( order_id,seller_id, valor_itens,frete_itens) as 
(
select i.order_id, i.seller_id, round(sum(i.price),2) as valor_itens, round(sum(i.freight_value),2) as frete_itens 
from olist.itens i
group by 1
order by 2 desc)
select *, round((frete_itens/(valor_itens+frete_itens))*100,2) as porcent_frete 
from percentfrete
order by 2);

#Como se dá a distribuição da distância entre os vendedores e os compradores?

#Nesta análise, será utilizada inicialmente a tabela de geolocalizações fornecida no dataset e, em seguida,
#cruzada com as tabelas de clientes e vendedores com o objetivo de determinar suas respectivas localizações.
#A tabela de localizações é formada por prefixo de CEPs do país e sus coordenadas geográficas (Latitude e Longitude)
#No entanto, o que se pode observar é que um CEP pode possuir mais de um par de coordenadas dado que uma rua não é somente
#um ponto, mas algo próximo a uma resta com vários pontos, desta forma, calculei um ponto médio para estas coordenadas
#com o objetivo de encontrar um ponto médio aproximado destas localizações, e assim, consiga ligar com outras localidades. 
 
create table olist.local_media(
select geolocation_zip_code_prefix, avg(geolocation_lat) as latitude, avg(geolocation_lng) as longitude 
from olist.localizacoes
group by 1);

#Neste trecho está sendo obtido o par de coordenadas dos pedidos realizados,a partir do cruzamento da tabela de pedidos
#com a tabela de localizações, utilizando como chave o prefixo dos CEPS, o qual foi obtido na tabela de clientes. 
#Outro ponto a se observar é que foram utilizados pedidos com status de entregue ou enviado, pois a análise está
#concentrada apenas nas entregas realmente realizadas ou em transporte. 

create table olist.pedidos_loc(
select o.*, l.latitude, l.longitude from
(select distinct p.order_id, p.customer_id,t.customer_zip_code_prefix,t.customer_city, t.customer_state
from olist.pedidos p 
join olist.clientes t on p.customer_id = t.customer_id
where p.order_status = "delivered" or p.order_status= "shipped") o  
join olist.local_media l on o.customer_zip_code_prefix = l.geolocation_zip_code_prefix);

#Aqui, fora realizado procedimento similar para obtenção das coordenadas dos clientes, porém agora iremos obter as localizações
#dos vendedores cadatrados.

create table olist.vendedores_loc(
select a.* from 
(select distinct i.order_id, i.seller_id, s.seller_zip_code_prefix,s.seller_city, s.seller_state
from olist.itens i 
left join olist.vendedores s on i.seller_id = s.seller_id) a
join olist.local_media l on a.seller_zip_code_prefix = l.geolocation_zip_code_prefix);

#Obtidas as localizações de vendedores e clientes, vamos calcular a distância entre eles, nos pedidos realizados.
#Para isto, utlizei a fórmula de Haversine,a qual é frenquentemente utilizada na navegação para cálculo da distância entre
#dois pontos de uma esfera a partir de suas coordenadas, logo, podemos utlizá-la ao aproximar a Terra como uma esfera.
create table olist.distancia_entregas(
select x.order_id,x.customer_city, x.customer_state, y.seller_id, y.seller_city, y.seller_state,
round(6371*2*asin(sqrt(pow(SIN(radians((y.latitude-x.latitude)/2)),2) + COS(radians(x.latitude)) * COS(radians(y.latitude)) * (pow(SIN(radians((y.longitude - x.longitude)/2)),2)))),2) as distancia
from olist.pedidos_loc x
join olist.vendedores_loc y on x.order_id = y.order_id);

#Calculadaas as distâncias, vamos agora agrupar as distâncias em categorias a partir de determinados intervalos
#Podemos iniciar descobrindo-se a menor e maior distancia para então definir os intervalos.

select min(distancia) as menor_distancia, max(distancia) as maior_distancia from olist.distancia_entregas;

#Neste trecho, incluímos uma coluna na tabela de distâncias das entregas para em seguida preenche-las com as 
#respectivas categorias. 

Alter table olist.distancia_entregas
add column categoria_distancia varchar(15);

set sql_safe_updates = 0;


update olist.distancia_entregas
set categoria_distancia =
case
	when distancia >= 0 and distancia <= 100 then 'Curta'
    when distancia >100 and distancia <= 500 then 'Média'
    when distancia > 500 and distancia <= 1000 then 'Longa'
    when distancia > 1000 THEN 'Muito longa'
    end;
    
    set sql_safe_updates = 1;
    
#Qual o tempo médio Real e estimado de entregas por categorias de distâncias?

#A partir da tabela de pedidos iremos calcular os tempos de entrega por pedido.
#Estes cálculos serão realizados através da diferenças entre as datas de compra e entrega e entre as datas estimada de entrega e de compra

with tempoentregs(order_id,tempo_de_entrega,estm_entrega) as
(
select order_id, 
datediff(cast(order_delivered_customer_date as datetime), cast(order_purchase_timestamp as datetime)) as tempo_de_entrega,
datediff(cast(order_estimated_delivery_date as datetime), cast(order_purchase_timestamp as datetime)) as estm_entrega 
from olist.pedidos 
where order_status = "delivered")
select t.*, tempo_de_entrega - estm_entrega as dif_tempentreg,s.categoria_distancia
from tempoentregs t
join olist.distancia_entregas s on t.order_id = s.order_id;
